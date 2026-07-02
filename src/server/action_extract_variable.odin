#+private file

package server

import "core:odin/ast"
import "core:strings"

import "src:common"

// Extract local variable: the user selects (or places the cursor on) an
// expression inside a procedure body; the action hoists it into a
// `new_variable := <expr>` declaration on its own line just above the enclosing
// statement and replaces the original occurrence with `new_variable`.

@(private = "package")
add_extract_variable_action :: proc(
	document: ^Document,
	range: common.Range,
	uri: string,
	actions: ^[dynamic]CodeAction,
) {
	sel, ok := common.get_absolute_range(range, document.text)
	if !ok {
		return
	}

	expr, stmt, found := find_extractable_expr(&document.ast, sel)
	if !found {
		return
	}

	src := document.ast.src
	if !hoist_preserves_semantics(src, stmt, expr) {
		return
	}

	expr_text := src[expr.pos.offset:expr.end.offset]
	indent := get_line_indentation(src, stmt.pos.offset)
	name := "new_variable"

	// Edit 1: insert the declaration on a new line above the enclosing statement.
	insert_pos := common.Position {
		line      = stmt.pos.line - 1,
		character = 0,
	}
	decl_edit := TextEdit {
		range   = {start = insert_pos, end = insert_pos},
		newText = strings.concatenate({indent, name, " := ", expr_text, "\n"}, context.temp_allocator),
	}

	// Edit 2: replace the original expression with the new variable name.
	replace_edit := TextEdit {
		range   = common.get_token_range(expr^, src),
		newText = name,
	}

	textEdits := make([dynamic]TextEdit, context.temp_allocator)
	append(&textEdits, decl_edit)
	append(&textEdits, replace_edit)

	workspaceEdit: WorkspaceEdit
	workspaceEdit.changes = make(map[string][]TextEdit, 0, context.temp_allocator)
	workspaceEdit.changes[uri] = textEdits[:]

	append(
		actions,
		CodeAction {
			kind = "refactor.extract",
			isPreferred = false,
			title = "Extract local variable",
			edit = workspaceEdit,
		},
	)
}

// Extract to struct field: inside an in-struct method body, hoist the selected
// expression onto a new field of the enclosing struct (placed after the last
// field, before the methods), replace the occurrence with the bare field name
// (reachable via the method's `using self`), and assign the value at the use
// site. Great for promoting a computed local into shared per-instance state.
@(private = "package")
add_extract_field_action :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	document: ^Document,
	range: common.Range,
	uri: string,
	actions: ^[dynamic]CodeAction,
) {
	st := position_context.struct_type
	if st == nil {
		return // only in-struct method bodies carry the struct node we insert into
	}

	sel, ok := common.get_absolute_range(range, document.text)
	if !ok {
		return
	}

	expr, stmt, found := find_extractable_expr(&document.ast, sel)
	if !found {
		return
	}

	// Don't offer it for the struct's own field-type expressions etc. — the
	// selection must sit inside a statement (a method body), which
	// find_extractable_expr already guarantees.
	src := document.ast.src
	if !hoist_preserves_semantics(src, stmt, expr) {
		return
	}

	expr_text := src[expr.pos.offset:expr.end.offset]

	type_str, type_ok := expr_type_string(ast_context, expr)
	if !type_ok {
		return // can't name the field's type — skip rather than emit broken code
	}

	name := "new_field"

	// Edit 1: insert `name: T,` into the struct, after the last field.
	field_pos, field_indent, field_ok := struct_member_insert_point(st, src, prefer_fields = true)
	if !field_ok {
		return
	}
	field_edit := TextEdit {
		range   = {start = field_pos, end = field_pos},
		newText = strings.concatenate({field_indent, name, ": ", type_str, ",\n"}, context.temp_allocator),
	}

	// Edit 2: assign the value at the use site, above the enclosing statement.
	stmt_indent := get_line_indentation(src, stmt.pos.offset)
	assign_pos := common.Position {
		line      = stmt.pos.line - 1,
		character = 0,
	}
	assign_edit := TextEdit {
		range   = {start = assign_pos, end = assign_pos},
		newText = strings.concatenate({stmt_indent, name, " = ", expr_text, "\n"}, context.temp_allocator),
	}

	// Edit 3: replace the original expression with the bare field name.
	replace_edit := TextEdit {
		range   = common.get_token_range(expr^, src),
		newText = name,
	}

	textEdits := make([dynamic]TextEdit, context.temp_allocator)
	append(&textEdits, field_edit)
	append(&textEdits, assign_edit)
	append(&textEdits, replace_edit)

	workspaceEdit: WorkspaceEdit
	workspaceEdit.changes = make(map[string][]TextEdit, 0, context.temp_allocator)
	workspaceEdit.changes[uri] = textEdits[:]

	append(
		actions,
		CodeAction {
			kind = "refactor.extract",
			isPreferred = false,
			title = "Extract to struct field",
			edit = workspaceEdit,
		},
	)
}

// Resolve an expression's type to a source-renderable string (with `^` prefixes
// for pointers), for use as a struct field type.
expr_type_string :: proc(ast_context: ^AstContext, expr: ^ast.Expr) -> (string, bool) {
	symbol, ok := resolve_type_expression(ast_context, expr)
	if !ok {
		return "", false
	}
	prefix := ""
	for _ in 0 ..< symbol.pointers {
		prefix = strings.concatenate({prefix, "^"}, context.temp_allocator)
	}
	if symbol.type_name != "" {
		return strings.concatenate({prefix, symbol.type_name}, context.temp_allocator), true
	}
	if symbol.name != "" {
		return strings.concatenate({prefix, symbol.name}, context.temp_allocator), true
	}
	return "", false
}

// Refuses hoists that would change behavior. The declaration is inserted on
// the line above the enclosing statement, so:
//   - the statement must be one whose evaluation is unconditional relative to
//     that line (no loops — a hoist out of a `for` header turns per-iteration
//     evaluation into once-before; no `if`/`switch` — a hoist above the guard
//     evaluates what the guard was protecting)
//   - the statement must start its own line (a `do`-body or `case x: stmt`
//     shares a line; a column-0 insert would tear it apart)
//   - the expression must not sit in a conditionally-evaluated position
//     inside the statement (`&&`/`||` right operand, ternary arms, `or_else`
//     fallback) or inside a nested proc literal (different scope)
hoist_preserves_semantics :: proc(src: string, stmt: ^ast.Stmt, expr: ^ast.Expr) -> bool {
	#partial switch _ in stmt.derived {
	case ^ast.Expr_Stmt, ^ast.Assign_Stmt, ^ast.Value_Decl, ^ast.Return_Stmt:
	// evaluation reaches the statement iff it reaches the inserted line
	case:
		return false
	}

	// The statement must be the first thing on its line.
	indent := get_line_indentation(src, stmt.pos.offset)
	if len(indent) != stmt.pos.column - 1 {
		return false
	}

	Hoist_Walk :: struct {
		expr:     ^ast.Expr,
		unsafe_:  bool,
	}

	contains_expr :: proc(node: ^ast.Node, expr: ^ast.Expr) -> bool {
		return node != nil && node.pos.offset <= expr.pos.offset && expr.end.offset <= node.end.offset
	}

	data := Hoist_Walk {
		expr = expr,
	}

	visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
		if node == nil {
			return nil
		}
		data := cast(^Hoist_Walk)visitor.data
		if data.unsafe_ {
			return nil
		}
		if node == cast(^ast.Node)data.expr {
			return nil // reached the expression itself; nothing below matters
		}
		if !contains_expr(node, data.expr) {
			return nil
		}

		#partial switch n in node.derived {
		case ^ast.Proc_Lit:
			data.unsafe_ = true
		case ^ast.Binary_Expr:
			if n.op.kind == .Cmp_And || n.op.kind == .Cmp_Or {
				if contains_expr(n.right, data.expr) {
					data.unsafe_ = true
				}
			}
		case ^ast.Ternary_If_Expr:
			if contains_expr(n.x, data.expr) || contains_expr(n.y, data.expr) {
				data.unsafe_ = true
			}
		case ^ast.Ternary_When_Expr:
			if contains_expr(n.x, data.expr) || contains_expr(n.y, data.expr) {
				data.unsafe_ = true
			}
		case ^ast.Or_Else_Expr:
			if contains_expr(n.y, data.expr) {
				data.unsafe_ = true
			}
		}
		return visitor
	}

	visitor := ast.Visitor {
		visit = visit,
		data  = &data,
	}
	ast.walk(&visitor, stmt)

	return !data.unsafe_
}

// An expression worth extracting into a variable (a value-producing expression,
// not a type or a statement). Bare names / literals are excluded for a
// zero-width cursor — extracting `x := x` is pointless — but allowed when the
// user explicitly selects them.
expr_is_extractable :: proc(node: ^ast.Node, trivial_ok: bool) -> bool {
	#partial switch _ in node.derived {
	case ^ast.Binary_Expr,
	     ^ast.Unary_Expr,
	     ^ast.Call_Expr,
	     ^ast.Selector_Expr,
	     ^ast.Selector_Call_Expr,
	     ^ast.Index_Expr,
	     ^ast.Matrix_Index_Expr,
	     ^ast.Slice_Expr,
	     ^ast.Paren_Expr,
	     ^ast.Comp_Lit,
	     ^ast.Deref_Expr,
	     ^ast.Type_Assertion,
	     ^ast.Or_Else_Expr,
	     ^ast.Ternary_If_Expr,
	     ^ast.Ternary_When_Expr:
		return true
	case ^ast.Ident, ^ast.Basic_Lit:
		return trivial_ok
	}
	return false
}

node_is_stmt :: proc(node: ^ast.Node) -> bool {
	#partial switch _ in node.derived {
	case ^ast.Bad_Stmt,
	     ^ast.Empty_Stmt,
	     ^ast.Expr_Stmt,
	     ^ast.Assign_Stmt,
	     ^ast.Block_Stmt,
	     ^ast.If_Stmt,
	     ^ast.When_Stmt,
	     ^ast.Return_Stmt,
	     ^ast.Defer_Stmt,
	     ^ast.For_Stmt,
	     ^ast.Range_Stmt,
	     ^ast.Inline_Range_Stmt,
	     ^ast.Case_Clause,
	     ^ast.Switch_Stmt,
	     ^ast.Type_Switch_Stmt,
	     ^ast.Branch_Stmt,
	     ^ast.Using_Stmt,
	     ^ast.Value_Decl:
		return true
	}
	return false
}

Extract_Walk :: struct {
	sel:       common.AbsoluteRange,
	best_expr: ^ast.Expr,
	best_stmt: ^ast.Stmt,
}

find_extractable_expr :: proc(
	file: ^ast.File,
	sel: common.AbsoluteRange,
) -> (
	^ast.Expr,
	^ast.Stmt,
	bool,
) {
	data := Extract_Walk {
		sel = sel,
	}

	visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
		if node == nil {
			return nil
		}
		data := cast(^Extract_Walk)visitor.data

		// Only descend into nodes that contain the whole selection.
		if !(node.pos.offset <= data.sel.start && data.sel.end <= node.end.offset) {
			return nil
		}

		trivial_ok := data.sel.start != data.sel.end
		if expr_is_extractable(node, trivial_ok) {
			expr := cast(^ast.Expr)node
			if data.best_expr == nil || span(node) < span(data.best_expr) {
				data.best_expr = expr
			}
		}
		if node_is_stmt(node) {
			stmt := cast(^ast.Stmt)node
			if data.best_stmt == nil || span(node) <= span(data.best_stmt) {
				data.best_stmt = stmt
			}
		}
		return visitor
	}

	visitor := ast.Visitor {
		visit = visit,
		data  = &data,
	}

	for decl in file.decls {
		ast.walk(&visitor, decl)
	}

	if data.best_expr == nil || data.best_stmt == nil {
		return nil, nil, false
	}
	// The expression must sit strictly inside the statement, otherwise there is
	// nothing to hoist (e.g. the selection is a whole statement).
	if data.best_expr.pos.offset == data.best_stmt.pos.offset &&
	   data.best_expr.end.offset == data.best_stmt.end.offset {
		return nil, nil, false
	}
	return data.best_expr, data.best_stmt, true
}

span :: proc(node: ^ast.Node) -> int {
	return node.end.offset - node.pos.offset
}
