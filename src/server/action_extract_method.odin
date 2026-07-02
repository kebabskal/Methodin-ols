#+private file

package server

import "core:odin/ast"
import "core:strings"

import "src:common"

// Extract method: the user selects one or more whole statements inside a
// procedure body; the action moves them into a new top-level procedure and
// replaces the selection with a call to it. Local variables that the selection
// reads but that are declared *before* it become value parameters (their types
// are taken from the declaration).
//
// The action is only offered when the resulting code keeps the original
// semantics: selections that return/defer/branch out of themselves, declare
// something the code after the selection still uses, or write to a captured
// (by-value) parameter are refused rather than silently miscompiled.

@(private = "package")
add_extract_method_action :: proc(
	ast_context: ^AstContext,
	document: ^Document,
	range: common.Range,
	uri: string,
	actions: ^[dynamic]CodeAction,
) {
	sel, ok := common.get_absolute_range(range, document.text)
	if !ok || sel.start == sel.end {
		return
	}

	stmts, block, top_decl, found := find_selected_statements(&document.ast, sel)
	if !found || len(stmts) == 0 {
		return
	}

	if !extraction_preserves_semantics(ast_context, stmts, block, sel) {
		return
	}

	src := document.ast.src
	method_name := "extracted_method"

	// Captured parameters: identifiers used in the selection that resolve to a
	// local declared before the selection.
	reset_ast_context(ast_context) // re-enable use_locals for type resolution of captured locals
	ast_context.current_package = ast_context.document_package
	params, params_ok := collect_captured_params(ast_context, stmts, sel)
	if !params_ok {
		return
	}

	// Build the parameter list and the matching argument list.
	param_list := strings.builder_make(context.temp_allocator)
	arg_list := strings.builder_make(context.temp_allocator)
	for p, i in params {
		if i > 0 {
			strings.write_string(&param_list, ", ")
			strings.write_string(&arg_list, ", ")
		}
		strings.write_string(&param_list, p.name)
		strings.write_string(&param_list, ": ")
		strings.write_string(&param_list, p.type_str)
		strings.write_string(&arg_list, p.name)
	}

	// The new procedure, inserted just above the enclosing top-level decl.
	proc_indent := get_line_indentation(src, top_decl.pos.offset)
	body := strings.builder_make(context.temp_allocator)
	for s in stmts {
		stmt_indent := get_line_indentation(src, s.pos.offset)
		strings.write_string(&body, proc_indent)
		strings.write_byte(&body, '\t')
		// Re-base the statement onto a single tab of indentation.
		_ = stmt_indent
		strings.write_string(&body, src[s.pos.offset:s.end.offset])
		strings.write_byte(&body, '\n')
	}

	new_proc := strings.concatenate(
		{
			method_name,
			" :: proc(",
			strings.to_string(param_list),
			") {\n",
			strings.to_string(body),
			proc_indent,
			"}\n\n",
			proc_indent,
		},
		context.temp_allocator,
	)

	insert_pos := common.Position {
		line      = top_decl_insert_line(top_decl),
		character = 0,
	}
	insert_edit := TextEdit {
		range   = {start = insert_pos, end = insert_pos},
		newText = new_proc,
	}

	// Replace the selected statements with a single call. The range starts at
	// the first statement itself (not column 0 — that would delete unrelated
	// code sharing the line), so the line's existing indentation is kept.
	first := stmts[0]
	last := stmts[len(stmts) - 1]
	call_text := strings.concatenate(
		{method_name, "(", strings.to_string(arg_list), ")"},
		context.temp_allocator,
	)
	replace_range := common.Range {
		start = common.get_token_range(first^, src).start,
		end   = common.get_token_range(last^, src).end,
	}
	replace_edit := TextEdit {
		range   = replace_range,
		newText = call_text,
	}

	textEdits := make([dynamic]TextEdit, context.temp_allocator)
	append(&textEdits, insert_edit)
	append(&textEdits, replace_edit)

	workspaceEdit: WorkspaceEdit
	workspaceEdit.changes = make(map[string][]TextEdit, 0, context.temp_allocator)
	workspaceEdit.changes[uri] = textEdits[:]

	append(
		actions,
		CodeAction {
			kind = "refactor.extract",
			isPreferred = false,
			title = "Extract method",
			edit = workspaceEdit,
		},
	)
}

// Extract statements into a new in-struct method: like extract-method, but the
// new procedure is placed inside the enclosing struct (so it has `using self`)
// and the selection is replaced with a bare call. `self` fields used in the
// selection stay reachable in the new method, so they are not captured as params.
@(private = "package")
add_extract_method_to_struct_action :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	document: ^Document,
	range: common.Range,
	uri: string,
	actions: ^[dynamic]CodeAction,
) {
	st := position_context.struct_type
	if st == nil {
		return
	}

	sel, ok := common.get_absolute_range(range, document.text)
	if !ok || sel.start == sel.end {
		return
	}

	stmts, block, _, found := find_selected_statements(&document.ast, sel)
	if !found || len(stmts) == 0 {
		return
	}

	if !extraction_preserves_semantics(ast_context, stmts, block, sel, allow_using_field_writes = true) {
		return
	}

	src := document.ast.src
	method_name := "new_method"
	reset_ast_context(ast_context) // re-enable use_locals for type resolution of captured locals
	ast_context.current_package = ast_context.document_package
	params, params_ok := collect_captured_params(ast_context, stmts, sel, exclude_using_fields = true)
	if !params_ok {
		return
	}

	param_list := strings.builder_make(context.temp_allocator)
	arg_list := strings.builder_make(context.temp_allocator)
	for p, i in params {
		if i > 0 {
			strings.write_string(&param_list, ", ")
			strings.write_string(&arg_list, ", ")
		}
		strings.write_string(&param_list, p.name)
		strings.write_string(&param_list, ": ")
		strings.write_string(&param_list, p.type_str)
		strings.write_string(&arg_list, p.name)
	}

	m_pos, m_indent, insert_ok := struct_member_insert_point(st, src)
	if !insert_ok {
		return
	}
	body := strings.builder_make(context.temp_allocator)
	for s in stmts {
		strings.write_string(&body, m_indent)
		strings.write_byte(&body, '\t')
		strings.write_string(&body, src[s.pos.offset:s.end.offset])
		strings.write_byte(&body, '\n')
	}

	// Trailing comma: in-struct method declarations are comma-separated members.
	new_method := strings.concatenate(
		{
			m_indent,
			method_name,
			" :: proc(",
			strings.to_string(param_list),
			") {\n",
			strings.to_string(body),
			m_indent,
			"},\n",
		},
		context.temp_allocator,
	)

	insert_edit := TextEdit {
		range   = {start = m_pos, end = m_pos},
		newText = new_method,
	}

	first := stmts[0]
	last := stmts[len(stmts) - 1]
	call_text := strings.concatenate(
		{method_name, "(", strings.to_string(arg_list), ")"},
		context.temp_allocator,
	)
	replace_edit := TextEdit {
		range = {start = common.get_token_range(first^, src).start, end = common.get_token_range(last^, src).end},
		newText = call_text,
	}

	textEdits := make([dynamic]TextEdit, context.temp_allocator)
	append(&textEdits, insert_edit)
	append(&textEdits, replace_edit)

	workspaceEdit: WorkspaceEdit
	workspaceEdit.changes = make(map[string][]TextEdit, 0, context.temp_allocator)
	workspaceEdit.changes[uri] = textEdits[:]

	append(
		actions,
		CodeAction {
			kind = "refactor.extract",
			isPreferred = false,
			title = "Extract to method",
			edit = workspaceEdit,
		},
	)
}

// Insert point for a new struct member: after the last method (or, with
// prefer_fields, after the last field so new fields land with the others),
// else after the last existing member kind, else just after the opening
// brace. Token lines are 1-based and LSP lines 0-based, so 0-based "line
// after token" == token.line; the result is clamped to the closing brace's
// line so a member whose last line is also the `}` line can't push the
// insertion outside the struct. Not offered for single-line structs — there
// is no line inside the braces to insert into.
@(private = "package")
struct_member_insert_point :: proc(
	st: ^ast.Struct_Type,
	src: string,
	prefer_fields := false,
) -> (
	common.Position,
	string,
	bool,
) {
	// The parser does not populate st.fields.open/close for these structs, so
	// the struct node's own pos/end anchor the braces: st.pos is on the
	// `struct {` line and st.end on the `}` line.
	if st.end.line <= st.pos.line {
		return {}, "", false
	}
	line_after :: proc(st: ^ast.Struct_Type, token_line: int) -> int {
		return min(token_line, st.end.line - 1)
	}
	if prefer_fields {
		if st.fields != nil && len(st.fields.list) > 0 {
			last := st.fields.list[len(st.fields.list) - 1]
			return common.Position{line = line_after(st, last.end.line), character = 0},
				get_line_indentation(src, last.pos.offset),
				true
		}
		if len(st.methods) > 0 {
			// No fields yet: a new field reads best above the methods.
			first := st.methods[0]
			return common.Position{line = first.pos.line - 1, character = 0},
				get_line_indentation(src, first.pos.offset),
				true
		}
	}
	if len(st.methods) > 0 {
		last := st.methods[len(st.methods) - 1]
		return common.Position{line = line_after(st, last.end.line), character = 0},
			get_line_indentation(src, last.pos.offset),
			true
	}
	if st.fields != nil && len(st.fields.list) > 0 {
		last := st.fields.list[len(st.fields.list) - 1]
		return common.Position{line = line_after(st, last.end.line), character = 0},
			get_line_indentation(src, last.pos.offset),
			true
	}
	return common.Position{line = line_after(st, st.pos.line), character = 0}, "\t", true
}

// The 0-based line to insert a new top-level proc on: above the enclosing
// decl AND above its doc comment and attributes, so they stay attached to
// the original declaration.
top_decl_insert_line :: proc(top_decl: ^ast.Node) -> int {
	line := top_decl.pos.line
	if vd, ok := top_decl.derived.(^ast.Value_Decl); ok {
		if vd.docs != nil && vd.docs.pos.line < line {
			line = vd.docs.pos.line
		}
		if len(vd.attributes) > 0 && vd.attributes[0].pos.line < line {
			line = vd.attributes[0].pos.line
		}
	}
	return line - 1
}

// Refuses selections whose extraction would silently change behavior:
//   - `return` returns from the new proc instead of the caller
//   - `defer` fires at the end of the new proc instead of the original scope
//   - `break`/`continue`/`fallthrough` targeting a loop/switch outside the
//     selection (labeled branches are refused wholesale — the label may sit
//     outside even when a loop is inside)
//   - a declaration the code after the selection still uses
//   - a write to a local captured by value (the caller's copy would stop
//     updating)
// Nested proc literals own their control flow and are skipped.
extraction_preserves_semantics :: proc(
	ast_context: ^AstContext,
	stmts: []^ast.Stmt,
	block: ^ast.Block_Stmt,
	sel: common.AbsoluteRange,
	allow_using_field_writes := false,
) -> bool {
	Span :: [2]int

	Flow_Walk :: struct {
		ast_context:             ^AstContext,
		sel:                     common.AbsoluteRange,
		declared:                map[string]bool, // block-level decls inside the selection
		loop_spans:              [dynamic]Span, // loops fully inside the selection
		switch_spans:            [dynamic]Span, // switches fully inside the selection
		allow_using_field_writes: bool,
		escapes:                 bool,
	}

	in_spans :: proc(spans: [dynamic]Span, offset: int) -> bool {
		// The branch belongs to its *innermost* enclosing loop/switch; if any
		// recorded span contains the offset, the innermost one is that span
		// or nested within it, hence also inside the selection.
		for span in spans {
			if span[0] <= offset && offset < span[1] {
				return true
			}
		}
		return false
	}

	data := Flow_Walk {
		ast_context              = ast_context,
		sel                      = sel,
		declared                 = make(map[string]bool, context.temp_allocator),
		loop_spans               = make([dynamic]Span, context.temp_allocator),
		switch_spans             = make([dynamic]Span, context.temp_allocator),
		allow_using_field_writes = allow_using_field_writes,
	}

	// Pass 1: record block-level declarations and the loop/switch spans the
	// branch checks below resolve against.
	for s in stmts {
		if vd, ok := s.derived.(^ast.Value_Decl); ok {
			for name_expr in vd.names {
				if ident, iok := name_expr.derived.(^ast.Ident); iok && ident.name != "_" {
					data.declared[ident.name] = true
				}
			}
		}
	}
	span_visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
		if node == nil {
			return nil
		}
		data := cast(^Flow_Walk)visitor.data
		#partial switch n in node.derived {
		case ^ast.Proc_Lit:
			return nil
		case ^ast.For_Stmt, ^ast.Range_Stmt, ^ast.Inline_Range_Stmt:
			append(&data.loop_spans, [2]int{node.pos.offset, node.end.offset})
		case ^ast.Switch_Stmt, ^ast.Type_Switch_Stmt:
			append(&data.switch_spans, [2]int{node.pos.offset, node.end.offset})
		}
		return visitor
	}
	span_visitor := ast.Visitor {
		visit = span_visit,
		data  = &data,
	}
	for s in stmts {
		ast.walk(&span_visitor, s)
	}

	// Pass 2: the actual escape checks.
	visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
		if node == nil {
			return nil
		}
		data := cast(^Flow_Walk)visitor.data
		if data.escapes {
			return nil
		}

		#partial switch n in node.derived {
		case ^ast.Proc_Lit:
			return nil // control flow inside a nested proc stays inside it
		case ^ast.Return_Stmt, ^ast.Defer_Stmt:
			data.escapes = true
			return nil
		case ^ast.Branch_Stmt:
			if n.label != nil {
				data.escapes = true // label target may be outside the selection
				return nil
			}
			offset := n.pos.offset
			#partial switch n.tok.kind {
			case .Continue: // targets the innermost loop
				data.escapes = !in_spans(data.loop_spans, offset)
			case .Break: // targets the innermost loop or switch
				data.escapes = !in_spans(data.loop_spans, offset) && !in_spans(data.switch_spans, offset)
			case .Fallthrough: // transfers within the switch
				data.escapes = !in_spans(data.switch_spans, offset)
			}
			return nil
		case ^ast.Assign_Stmt:
			// A write to a pre-selection local captured by value silently
			// stops updating the caller's variable. `using self` fields are
			// exempt when the target is an in-struct method — they are
			// reached through the self pointer, not captured.
			for lhs in n.lhs {
				ident, is_ident := lhs.derived.(^ast.Ident)
				if !is_ident || ident.name == "_" {
					continue
				}
				if data.declared[ident.name] {
					continue // writes a selection-local decl, not a capture
				}
				if local, ok := get_local(data.ast_context^, ident^); ok {
					if data.allow_using_field_writes && .UsingField in local.flags {
						continue
					}
					if local.offset <= data.sel.start && !local.local_global {
						data.escapes = true
						return nil
					}
				}
			}
		}
		return visitor
	}
	visitor := ast.Visitor {
		visit = visit,
		data  = &data,
	}
	for s in stmts {
		ast.walk(&visitor, s)
		if data.escapes {
			return false
		}
	}

	// A block-level decl from the selection that is still used afterwards
	// would become undeclared at its remaining use sites.
	if len(data.declared) > 0 && block != nil {
		sel_end := stmts[len(stmts) - 1].end.offset
		Use_Walk :: struct {
			declared: ^map[string]bool,
			used:     bool,
		}
		use_data := Use_Walk {
			declared = &data.declared,
		}
		use_visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
			if node == nil {
				return nil
			}
			d := cast(^Use_Walk)visitor.data
			if d.used {
				return nil
			}
			if ident, ok := node.derived.(^ast.Ident); ok {
				if d.declared[ident.name] {
					d.used = true
				}
			}
			return visitor
		}
		use_visitor := ast.Visitor {
			visit = use_visit,
			data  = &use_data,
		}
		for s in block.stmts {
			if s == nil || s.pos.offset < sel_end {
				continue
			}
			ast.walk(&use_visitor, s)
			if use_data.used {
				return false
			}
		}
	}

	return true
}

Captured_Param :: struct {
	name:     string,
	type_str: string,
}

// Collects locals referenced inside the selection that are declared before it
// (in ast_context.locals, which get_locals populated at the selection start).
// Fails (ok=false) when a captured local's type can't be rendered — emitting
// the extraction anyway would produce an undeclared identifier — or when a
// captured name is re-declared inside the selection (it would collide with
// the parameter in the extracted proc's scope).
collect_captured_params :: proc(
	ast_context: ^AstContext,
	stmts: []^ast.Stmt,
	sel: common.AbsoluteRange,
	exclude_using_fields := false,
) -> (
	[]Captured_Param,
	bool,
) {
	params := make([dynamic]Captured_Param, context.temp_allocator)
	seen := make(map[string]bool, context.temp_allocator)

	// Names declared *inside* the selection, mapped to their decl offset.
	// ast_context.locals is a snapshot taken at the selection start, so
	// get_local can't see these — an ident matching one (at or after its
	// decl) refers to the inner decl, not to an outer capturable local.
	declared_inside := make(map[string]int, context.temp_allocator)

	Capture_Walk :: struct {
		ast_context:          ^AstContext,
		params:               ^[dynamic]Captured_Param,
		seen:                 ^map[string]bool,
		declared_inside:      ^map[string]int,
		sel:                  common.AbsoluteRange,
		exclude_using_fields: bool,
		failed:               bool,
	}

	data := Capture_Walk {
		ast_context          = ast_context,
		params               = &params,
		seen                 = &seen,
		declared_inside      = &declared_inside,
		sel                  = sel,
		exclude_using_fields = exclude_using_fields,
	}

	decl_visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
		if node == nil {
			return nil
		}
		data := cast(^Capture_Walk)visitor.data
		if vd, ok := node.derived.(^ast.Value_Decl); ok {
			for name_expr in vd.names {
				if ident, iok := name_expr.derived.(^ast.Ident); iok && ident.name != "" && ident.name != "_" {
					if ident.name not_in data.declared_inside {
						data.declared_inside[ident.name] = ident.pos.offset
					}
				}
			}
		}
		return visitor
	}

	visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
		if node == nil {
			return nil
		}
		data := cast(^Capture_Walk)visitor.data
		if data.failed {
			return nil
		}

		// Member names aren't uses of same-named locals: `obj.x` reads the
		// field `x`, `V{x = 1}` names a struct field, `f(x = 1)` names a
		// parameter. Walk only the value side of each.
		#partial switch n in node.derived {
		case ^ast.Selector_Expr:
			ast.walk(visitor, n.expr)
			return nil
		case ^ast.Implicit_Selector_Expr:
			return nil
		case ^ast.Field_Value:
			ast.walk(visitor, n.value)
			return nil
		}

		if ident, is_ident := node.derived.(^ast.Ident); is_ident {
			name := ident.name
			if name == "" || name == "_" {
				return visitor
			}
			// Shadowed by a decl inside the selection at this point?
			if decl_offset, inside := data.declared_inside[name]; inside && ident.pos.offset >= decl_offset {
				// If the name was ALSO captured (used before the inner
				// decl), the parameter and the re-declaration collide in
				// the extracted proc's scope.
				if data.seen[name] {
					data.failed = true
					return nil
				}
				return visitor
			}
			if data.seen[name] {
				return visitor
			}
			if local, ok := get_local(data.ast_context^, ident^); ok {
				// For struct-method extraction, `using self` fields stay reachable
				// in the new in-struct method — don't capture them as params.
				if data.exclude_using_fields && .UsingField in local.flags {
					return visitor
				}
				// Declared before the selection → a captured parameter.
				if local.offset <= data.sel.start && !local.local_global {
					type_str, tok := local_type_string(data.ast_context, local)
					if !tok {
						data.failed = true
						return nil
					}
					data.seen[name] = true
					append(data.params, Captured_Param{name = name, type_str = type_str})
				}
			}
		}
		return visitor
	}

	decl_visitor := ast.Visitor {
		visit = decl_visit,
		data  = &data,
	}
	visitor := ast.Visitor {
		visit = visit,
		data  = &data,
	}
	for s in stmts {
		ast.walk(&decl_visitor, s)
	}
	for s in stmts {
		ast.walk(&visitor, s)
		if data.failed {
			return {}, false
		}
	}

	return params[:], true
}

// Renders a local's type. Prefers the explicit type annotation; otherwise
// resolves the declaration's inferred type to a name.
local_type_string :: proc(ast_context: ^AstContext, local: DocumentLocal) -> (string, bool) {
	if local.type_expr != nil {
		return node_to_string(local.type_expr), true
	}
	if local.rhs != nil {
		if symbol, ok := resolve_type_expression(ast_context, local.rhs); ok {
			if symbol.type_name != "" {
				prefix := ""
				for _ in 0 ..< symbol.pointers {
					prefix = strings.concatenate({prefix, "^"}, context.temp_allocator)
				}
				return strings.concatenate({prefix, symbol.type_name}, context.temp_allocator), true
			}
			if symbol.name != "" {
				return symbol.name, true
			}
		}
	}
	return "", false
}

// Finds the maximal run of whole statements within `sel` that share a block,
// the block itself (for use-after-selection checks), and the enclosing
// top-level declaration (for insertion point).
find_selected_statements :: proc(
	file: ^ast.File,
	sel: common.AbsoluteRange,
) -> (
	[]^ast.Stmt,
	^ast.Block_Stmt,
	^ast.Node,
	bool,
) {
	// The top-level declaration that contains the selection.
	top_decl: ^ast.Node
	for decl in file.decls {
		if decl.pos.offset <= sel.start && sel.end <= decl.end.offset {
			top_decl = decl
			break
		}
	}
	if top_decl == nil {
		return nil, nil, nil, false
	}

	// Find the innermost block that contains the selection, then take its
	// statements fully inside the selection.
	Block_Walk :: struct {
		sel:   common.AbsoluteRange,
		block: ^ast.Block_Stmt,
	}
	data := Block_Walk {
		sel = sel,
	}
	visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
		if node == nil {
			return nil
		}
		data := cast(^Block_Walk)visitor.data
		if !(node.pos.offset <= data.sel.start && data.sel.end <= node.end.offset) {
			return nil
		}
		if block, ok := node.derived.(^ast.Block_Stmt); ok {
			data.block = block
		}
		return visitor
	}
	visitor := ast.Visitor {
		visit = visit,
		data  = &data,
	}
	ast.walk(&visitor, top_decl)

	if data.block == nil {
		return nil, nil, nil, false
	}

	selected := make([dynamic]^ast.Stmt, context.temp_allocator)
	for s in data.block.stmts {
		if s == nil {
			continue
		}
		if sel.start <= s.pos.offset && s.end.offset <= sel.end {
			append(&selected, s)
		}
	}

	if len(selected) == 0 {
		return nil, nil, nil, false
	}
	return selected[:], data.block, top_decl, true
}
