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
