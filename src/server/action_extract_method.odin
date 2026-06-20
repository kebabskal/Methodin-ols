#+private file

package server

import "core:odin/ast"
import "core:strings"

import "src:common"

// Extract method: the user selects one or more whole statements inside a
// procedure body; the action moves them into a new top-level procedure and
// replaces the selection with a call to it. Local variables that the selection
// reads but that are declared *before* it become value parameters (their types
// are taken from the declaration). Variables declared inside the selection and
// used afterwards are not handled — see the limitation note in the title-less
// guard below; such selections are still extractable but may need manual
// fix-up of return values.

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

	stmts, top_decl, found := find_selected_statements(&document.ast, sel)
	if !found || len(stmts) == 0 {
		return
	}

	src := document.ast.src
	method_name := "extracted_method"

	// Captured parameters: identifiers used in the selection that resolve to a
	// local declared before the selection.
	params := collect_captured_params(ast_context, stmts, sel)

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
		line      = top_decl.pos.line - 1,
		character = 0,
	}
	insert_edit := TextEdit {
		range   = {start = insert_pos, end = insert_pos},
		newText = new_proc,
	}

	// Replace the selected statements with a single call.
	first := stmts[0]
	last := stmts[len(stmts) - 1]
	call_indent := get_line_indentation(src, first.pos.offset)
	call_text := strings.concatenate(
		{call_indent, method_name, "(", strings.to_string(arg_list), ")"},
		context.temp_allocator,
	)
	replace_range := common.Range {
		start = {line = first.pos.line - 1, character = 0},
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

Captured_Param :: struct {
	name:     string,
	type_str: string,
}

// Collects locals referenced inside the selection that are declared before it
// (in ast_context.locals, which get_locals populated at the selection start).
collect_captured_params :: proc(
	ast_context: ^AstContext,
	stmts: []^ast.Stmt,
	sel: common.AbsoluteRange,
) -> []Captured_Param {
	params := make([dynamic]Captured_Param, context.temp_allocator)
	seen := make(map[string]bool, context.temp_allocator)

	Capture_Walk :: struct {
		ast_context: ^AstContext,
		params:      ^[dynamic]Captured_Param,
		seen:        ^map[string]bool,
		sel:         common.AbsoluteRange,
	}

	data := Capture_Walk {
		ast_context = ast_context,
		params      = &params,
		seen        = &seen,
		sel         = sel,
	}

	visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
		if node == nil {
			return nil
		}
		data := cast(^Capture_Walk)visitor.data

		if ident, is_ident := node.derived.(^ast.Ident); is_ident {
			name := ident.name
			if name == "" || name == "_" || data.seen[name] {
				return visitor
			}
			if local, ok := get_local(data.ast_context^, ident^); ok {
				// Declared before the selection → a captured parameter.
				if local.offset <= data.sel.start && !local.local_global {
					type_str, tok := local_type_string(data.ast_context, local)
					if tok {
						data.seen[name] = true
						append(data.params, Captured_Param{name = name, type_str = type_str})
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
	}

	return params[:]
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
// and the enclosing top-level declaration (for insertion point).
find_selected_statements :: proc(
	file: ^ast.File,
	sel: common.AbsoluteRange,
) -> (
	[]^ast.Stmt,
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
		return nil, nil, false
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
		return nil, nil, false
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
		return nil, nil, false
	}
	return selected[:], top_decl, true
}
