#+private file

package server

import "core:fmt"
import "core:odin/ast"
import "core:strings"

import "src:common"

// Generate missing method: on a call `x.foo(...)` where `foo` is neither a field
// nor a method of x's struct, offer "Create method foo on T" — insert a stub
// into the struct (after its existing methods), with one parameter per call
// argument, typed from the argument. Scoped to structs defined in the current
// file (that is where we can find the struct body to insert into).
@(private = "package")
add_generate_method_action :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	document: ^Document,
	uri: string,
	actions: ^[dynamic]CodeAction,
) {
	if position_context.selector == nil {
		return
	}

	// Extract (base expression, method name) from either shape:
	//   `w.foo`      -> Selector_Expr: field is the Ident, selector is the base.
	//   `w.foo(...)` -> Selector_Call_Expr: selector holds the `w.foo` selector.
	base_expr: ^ast.Expr
	method_name: string
	if field_ident, ok := position_context.field.derived.(^ast.Ident); ok {
		base_expr = position_context.selector
		method_name = field_ident.name
	} else if sel, ok := position_context.selector.derived.(^ast.Selector_Expr); ok {
		base_expr = sel.expr
		if fid, fok := sel.field.derived.(^ast.Ident); fok {
			method_name = fid.name
		}
	}
	if base_expr == nil || method_name == "" {
		return
	}

	reset_ast_context(ast_context) // re-enable use_locals (get_locals leaves it off)
	ast_context.current_package = ast_context.document_package

	base, ok := resolve_type_expression(ast_context, base_expr)
	if !ok {
		return
	}
	sv, is_struct := base.value.(SymbolStructValue)
	if !is_struct {
		return
	}

	// Already a field?
	for name in sv.names {
		if name == method_name {
			return
		}
	}
	// Already a method (in the receiver type's method bucket)?
	if pkg, pok := indexer.index.collection.packages[base.pkg]; pok {
		if bucket, bok := pkg.methods[Method{pkg = base.pkg, name = base.name}]; bok {
			for m in bucket {
				if m.name == method_name {
					return
				}
			}
		}
	}

	// Find the struct's body in THIS file so we know where to insert.
	st, st_ok := find_struct_type_in_file(&document.ast, base.name)
	if !st_ok {
		return
	}

	src := document.ast.src
	params := ""
	if position_context.call != nil {
		if call, cok := position_context.call.derived.(^ast.Call_Expr); cok {
			params = infer_param_list(ast_context, call.args)
		}
	}

	pos, indent := method_insert_point(st, src)
	stub := strings.concatenate(
		{indent, method_name, " :: proc(", params, ") {\n", indent, "\t\n", indent, "}\n"},
		context.temp_allocator,
	)

	edit := TextEdit {
		range   = {start = pos, end = pos},
		newText = stub,
	}

	textEdits := make([dynamic]TextEdit, context.temp_allocator)
	append(&textEdits, edit)

	workspaceEdit: WorkspaceEdit
	workspaceEdit.changes = make(map[string][]TextEdit, 0, context.temp_allocator)
	workspaceEdit.changes[uri] = textEdits[:]

	append(
		actions,
		CodeAction {
			kind = "refactor.rewrite",
			isPreferred = false,
			title = fmt.tprintf("Create method %s on %s", method_name, base.name),
			edit = workspaceEdit,
		},
	)
}

// Build `a0: T0, a1: T1, ...` from a call's arguments, typed by resolution.
infer_param_list :: proc(ast_context: ^AstContext, args: []^ast.Expr) -> string {
	if len(args) == 0 {
		return ""
	}
	sb := strings.builder_make(context.temp_allocator)
	for arg, i in args {
		if i > 0 {
			strings.write_string(&sb, ", ")
		}
		type_str := "int"
		if sym, ok := resolve_type_expression(ast_context, arg); ok {
			prefix := ""
			for _ in 0 ..< sym.pointers {
				prefix = strings.concatenate({prefix, "^"}, context.temp_allocator)
			}
			if sym.type_name != "" {
				type_str = strings.concatenate({prefix, sym.type_name}, context.temp_allocator)
			} else if sym.name != "" {
				type_str = strings.concatenate({prefix, sym.name}, context.temp_allocator)
			}
		}
		fmt.sbprintf(&sb, "a%d: %s", i, type_str)
	}
	return strings.to_string(sb)
}

// Locate a top-level `Name :: struct { ... }` in the file and return its
// Struct_Type node.
find_struct_type_in_file :: proc(file: ^ast.File, name: string) -> (^ast.Struct_Type, bool) {
	for decl in file.decls {
		vd, vd_ok := decl.derived.(^ast.Value_Decl)
		if !vd_ok || len(vd.names) != 1 || len(vd.values) != 1 {
			continue
		}
		ident, id_ok := vd.names[0].derived.(^ast.Ident)
		if !id_ok || ident.name != name {
			continue
		}
		value := vd.values[0]
		if paren, is_paren := value.derived.(^ast.Paren_Expr); is_paren {
			value = paren.expr
		}
		if st, is_st := value.derived.(^ast.Struct_Type); is_st {
			return st, true
		}
	}
	return nil, false
}

// Insert a new method after the last existing method, else after the last
// field, else just after the opening brace.
method_insert_point :: proc(st: ^ast.Struct_Type, src: string) -> (common.Position, string) {
	if len(st.methods) > 0 {
		last := st.methods[len(st.methods) - 1]
		return common.Position{line = last.end.line, character = 0}, get_line_indentation(src, last.pos.offset)
	}
	if st.fields != nil && len(st.fields.list) > 0 {
		last := st.fields.list[len(st.fields.list) - 1]
		return common.Position{line = last.end.line, character = 0}, get_line_indentation(src, last.pos.offset)
	}
	return common.Position{line = st.fields.open.line, character = 0}, "\t"
}
