package server

import "core:fmt"
import "core:odin/ast"
import "core:strings"

import "src:common"


@(private)
create_remove_edit :: proc(
	position_context: ^DocumentPositionContext,
	strip_leading_period := false,
) -> (
	[]TextEdit,
	bool,
) {
	range, ok := get_range_from_selection_start_to_dot(position_context)

	if !ok {
		return {}, false
	}

	remove_range := common.Range {
		start = range.start,
		end   = range.end,
	}

	if strip_leading_period {
		remove_range.end.character -= 1
	}

	remove_edit := TextEdit {
		range   = remove_range,
		newText = "",
	}

	additionalTextEdits := make([]TextEdit, 1, context.temp_allocator)
	additionalTextEdits[0] = remove_edit

	return additionalTextEdits, true
}

append_method_completion :: proc(
	ast_context: ^AstContext,
	selector_symbol: Symbol,
	position_context: ^DocumentPositionContext,
	results: ^[dynamic]CompletionResult,
	receiver: string,
) {
	if selector_symbol.type != .Variable && selector_symbol.type != .Struct && selector_symbol.type != .Field {
		return
	}

	if value, ok := selector_symbol.value.(SymbolUntypedValue); ok {
		cases := untyped_map[value.type]
		for c in cases {
			method := Method {
				name = c,
				pkg  = "$builtin", // Untyped values are always builtin types
			}
			collect_methods(ast_context, position_context, method, results)
		}
	} else {
		// For typed values, check if it's a builtin type
		method_pkg := selector_symbol.pkg
		if is_builtin_type_name(selector_symbol.name) {
			method_pkg = "$builtin"
		}
		method := Method {
			name = selector_symbol.name,
			pkg  = method_pkg,
		}
		collect_methods(ast_context, position_context, method, results)
	}

	// Methodin: promote methods from `using`-embedded structs (transitively), so
	// e.g. `ChaserEnemy` (embeds `EnemyBase`, which embeds `Transform`) offers
	// Transform's and EnemyBase's methods too — mirroring how the compiler makes
	// them callable via UFCS on the derived value.
	if _, is_struct := selector_symbol.value.(SymbolStructValue); is_struct {
		seen := make(map[string]bool, 0, context.temp_allocator)
		seen[strings.concatenate({selector_symbol.pkg, "/", selector_symbol.name}, context.temp_allocator)] = true
		collect_using_methods(ast_context, position_context, selector_symbol, results, &seen, 0)
	}

	// Fixed-array receivers (e.g. linalg vectors) have no named type to key
	// methods on, but UFCS reaches array-receiver free procs through any
	// in-scope import. Offer those, indexed under the synthetic `$array` key.
	#partial switch _ in selector_symbol.value {
	case SymbolFixedArrayValue:
		collect_in_scope_array_methods(ast_context, position_context, results)
	}
}

@(private = "file")
collect_in_scope_array_methods :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	results: ^[dynamic]CompletionResult,
) {
	method := Method{pkg = "$builtin", name = "$array"}

	pkgs := make([dynamic]string, context.temp_allocator)
	if ast_context.current_package != "" {
		append(&pkgs, ast_context.current_package)
	}
	for imp in ast_context.imports {
		append(&pkgs, imp.name)
	}

	for pkg_path in pkgs {
		// Ensure the package is indexed — core/vendor packages are built lazily,
		// and their `$array` method bucket only exists once collected.
		try_build_package(pkg_path)
		v, ok := indexer.index.collection.packages[pkg_path]
		if !ok {
			continue
		}
		symbols, syms_ok := &v.methods[method]
		if !syms_ok {
			continue
		}
		for &symbol in symbols {
			if should_skip_private_symbol(symbol, ast_context.current_package, ast_context.uri) {
				continue
			}
			resolve_unresolved_symbol(ast_context, &symbol)

			#partial switch &sym_value in symbol.value {
			case SymbolProcedureValue:
				add_proc_method_completion(ast_context, &symbol, sym_value, results)
			case SymbolProcedureGroupValue:
				add_proc_group_method_completion(ast_context, &symbol, sym_value, results)
			}
		}
	}
}

@(private = "file")
collect_using_methods :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	struct_symbol: Symbol,
	results: ^[dynamic]CompletionResult,
	seen: ^map[string]bool,
	depth: int,
) {
	if depth > 32 {
		return
	}
	sv, is_struct := struct_symbol.value.(SymbolStructValue)
	if !is_struct {
		return
	}
	for using_idx in sv.usings {
		if using_idx < 0 || using_idx >= len(sv.types) {
			continue
		}
		embedded, ok := resolve_type_expression(ast_context, sv.types[using_idx])
		if !ok {
			continue
		}
		if _, embedded_is_struct := embedded.value.(SymbolStructValue); !embedded_is_struct {
			continue
		}
		key := strings.concatenate({embedded.pkg, "/", embedded.name}, context.temp_allocator)
		if key in seen {
			continue // guards diamond / cyclic `using` graphs
		}
		seen[key] = true

		method_pkg := embedded.pkg
		if is_builtin_type_name(embedded.name) {
			method_pkg = "$builtin"
		}
		collect_methods(ast_context, position_context, Method{name = embedded.name, pkg = method_pkg}, results)
		collect_using_methods(ast_context, position_context, embedded, results, seen, depth + 1)
	}
}

@(private = "file")
collect_methods :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	method: Method,
	results: ^[dynamic]CompletionResult,
) {
	// UFCS only resolves a free proc when it lives in the receiver type's
	// defining package (or "$builtin" for built-in scalars / containers),
	// so only look there — every other package's hit would produce code
	// the compiler refuses to compile.
	v, ok := indexer.index.collection.packages[method.pkg]
	if !ok {
		return
	}
	symbols, syms_ok := &v.methods[method]
	if !syms_ok {
		return
	}

	for &symbol in symbols {
		if should_skip_private_symbol(symbol, ast_context.current_package, ast_context.uri) {
			continue
		}
		resolve_unresolved_symbol(ast_context, &symbol)

		#partial switch &sym_value in symbol.value {
		case SymbolProcedureValue:
			add_proc_method_completion(ast_context, &symbol, sym_value, results)
		case SymbolProcedureGroupValue:
			add_proc_group_method_completion(ast_context, &symbol, sym_value, results)
		}
	}
}

@(private = "file")
add_proc_method_completion :: proc(
	ast_context: ^AstContext,
	symbol: ^Symbol,
	value: SymbolProcedureValue,
	results: ^[dynamic]CompletionResult,
) {
	if len(value.arg_types) == 0 || value.arg_types[0] == nil || value.arg_types[0].type == nil {
		return
	}
	args := build_ufcs_arg_snippet(value.arg_types)
	append_ufcs_item(ast_context, symbol, args, results)
}

@(private = "file")
add_proc_group_method_completion :: proc(
	ast_context: ^AstContext,
	symbol: ^Symbol,
	value: SymbolProcedureGroupValue,
	results: ^[dynamic]CompletionResult,
) {
	proc_group, is_group := value.group.derived.(^ast.Proc_Group)
	if !is_group || len(proc_group.args) == 0 {
		return
	}

	// Different overloads can have different params; a per-arg snippet
	// would only be right for one of them. Insert a single tab stop and
	// let signature help disambiguate.
	args := ""
	for member_expr in proc_group.args {
		member, ok := resolve_type_expression(ast_context, member_expr)
		if !ok {
			continue
		}
		if proc_val, is_proc_val := member.value.(SymbolProcedureValue); is_proc_val {
			if len(proc_val.arg_types) > 1 {
				args = "$0"
				break
			}
		}
	}

	append_ufcs_item(ast_context, symbol, args, results)
}

@(private = "file")
build_ufcs_arg_snippet :: proc(arg_types: []^ast.Field) -> string {
	// Skip arg_types[0] — UFCS supplies the receiver. For each remaining
	// field, emit one ${N:name} placeholder per declared name; for a
	// variadic last arg, emit a single ${N:..name} stop. After the last
	// placeholder we leave $0 outside the parens so Tab exits the call.
	if len(arg_types) <= 1 {
		return ""
	}

	sb := strings.builder_make(context.temp_allocator)
	stop := 1

	for field, fi in arg_types[1:] {
		variadic := false
		if field.type != nil {
			_, variadic = field.type.derived.(^ast.Ellipsis)
		}

		for name_expr, ni in field.names {
			ident, is_ident := name_expr.derived.(^ast.Ident)
			if !is_ident {
				continue
			}
			if stop > 1 {
				strings.write_string(&sb, ", ")
			}
			// fmt.sbprintf reads `{` as a directive opener, so write the
			// literal `${…}` snippet braces around the formatted bits.
			strings.write_string(&sb, "${")
			fmt.sbprint(&sb, stop)
			strings.write_string(&sb, ":")
			if variadic {
				strings.write_string(&sb, "..")
			}
			strings.write_string(&sb, ident.name)
			strings.write_string(&sb, "}")
			stop += 1
			_ = ni
			_ = fi
		}
	}

	return strings.to_string(sb)
}

@(private = "file")
append_ufcs_item :: proc(
	ast_context: ^AstContext,
	symbol: ^Symbol,
	args_snippet: string,
	results: ^[dynamic]CompletionResult,
) {
	// `x.foo` is left literal; we insert just the method name plus a
	// tab-able placeholder per parameter (skipping the UFCS receiver).
	insert_text: string
	if args_snippet == "" {
		insert_text = fmt.tprintf("%v()$0", symbol.name)
	} else {
		insert_text = fmt.tprintf("%v(%v)$0", symbol.name, args_snippet)
	}

	item := CompletionItem {
		label            = symbol.name,
		kind             = symbol_type_to_completion_kind(symbol.type),
		detail           = get_short_signature(ast_context, symbol^),
		insertText       = insert_text,
		insertTextFormat = .Snippet,
		documentation    = construct_symbol_docs(symbol^),
		command          = Command{command = "editor.action.triggerParameterHints"},
	}

	append(results, CompletionResult{completion_item = item})
}
