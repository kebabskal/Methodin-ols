package server

import "core:odin/ast"

import "src:common"

get_document_symbols :: proc(document: ^Document) -> []DocumentSymbol {
	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
	)

	get_globals(document.ast, &ast_context)

	symbols := make([dynamic]DocumentSymbol, context.temp_allocator)

	package_symbol: DocumentSymbol

	if len(document.ast.decls) == 0 {
		return {}
	}

	for k, global in ast_context.globals {
		symbol: DocumentSymbol
		symbol.selectionRange = common.get_token_range(global.name_expr, ast_context.file.src)
		symbol.range = common.get_token_range(global.expr, ast_context.file.src)
		ensure_selection_range_contained(&symbol.range, symbol.selectionRange)
		symbol.name = k

		#partial switch v in global.expr.derived {
		case ^ast.Struct_Type, ^ast.Bit_Field_Type:
			// TODO: this only does the top level fields, we may want to travers all the way down in the future
			if s, ok := resolve_type_expression(&ast_context, global.expr); ok {
				#partial switch v in s.value {
				case SymbolStructValue:
					children := make([dynamic]DocumentSymbol, context.temp_allocator)
					for name, i in v.names {
						if name == "" {
							continue
						}
						child: DocumentSymbol
						child.range = v.ranges[i]
						child.selectionRange = v.ranges[i]
						child.name = name
						child.kind = .Field
						append(&children, child)
					}
					symbol.children = children[:]
				case SymbolBitFieldValue:
					children := make([dynamic]DocumentSymbol, context.temp_allocator)
					for name, i in v.names {
						if name == "" {
							continue
						}
						child: DocumentSymbol
						child.range = v.ranges[i]
						child.selectionRange = v.ranges[i]
						child.name = name
						child.kind = .Field
						append(&children, child)
					}
					symbol.children = children[:]
				}
			}

			// Methodin: in-struct methods (`Foo :: struct { bar :: proc(){} }`)
			// are stored on the raw Struct_Type AST node, not in the resolved
			// struct value. Emit each as a nested `.Method` child alongside the
			// struct's fields.
			if st, is_struct := global.expr.derived.(^ast.Struct_Type); is_struct && len(st.methods) > 0 {
				children := make([dynamic]DocumentSymbol, context.temp_allocator)
				append(&children, ..symbol.children)
				for m in st.methods {
					if method, ok := make_method_document_symbol(m, ast_context.file.src); ok {
						append(&children, method)
					}
				}
				symbol.children = children[:]
			}

			symbol.kind = .Struct
		case ^ast.Proc_Lit, ^ast.Proc_Group:
			symbol.kind = .Function
		case ^ast.Enum_Type, ^ast.Union_Type:
			symbol.kind = .Enum
		case ^ast.Comp_Lit:
			if s, ok := resolve_type_expression(&ast_context, v); ok {
				ranges :: struct {
					range: common.Range,
					selection_range: common.Range,
				}
				name_map := make(map[string]ranges)
				for elem in v.elems {
					if field_value, ok := elem.derived.(^ast.Field_Value); ok {
						if name, ok := field_value.field.derived.(^ast.Ident); ok {
							selection_range := common.get_token_range(name, ast_context.file.src)
							range := common.get_token_range(field_value, ast_context.file.src)
							ensure_selection_range_contained(&range, selection_range)
							name_map[name.name] = {
								range = range,
								selection_range = selection_range,
							}
						}
					}
				}
				#partial switch v in s.value {
				case SymbolStructValue:
					children := make([dynamic]DocumentSymbol, context.temp_allocator)
					for name, i in v.names {
						child: DocumentSymbol
						if range, ok := name_map[name]; ok {
							child.range = range.range
							child.selectionRange = range.selection_range
							child.name = name
							child.kind = .Field
							append(&children, child)
						}
					}
					symbol.children = children[:]
				case SymbolBitFieldValue:
					children := make([dynamic]DocumentSymbol, context.temp_allocator)
					for name, i in v.names {
						child: DocumentSymbol
						if range, ok := name_map[name]; ok {
							child.range = range.range
							child.selectionRange = range.selection_range
							child.name = name
							child.kind = .Field
							append(&children, child)
						}
					}
					symbol.children = children[:]
				}
			}
		case:
			symbol.kind = .Variable
		}

		append(&symbols, symbol)
	}

	// Methodin: `impl <Type> { ... }` blocks are not Value_Decls, so they
	// never make it into ast_context.globals. Walk the raw decls and emit
	// each impl block as a container symbol whose methods are `.Method`
	// children.
	for decl in document.ast.decls {
		impl, ok := decl.derived.(^ast.Impl_Block)
		if !ok {
			continue
		}

		container: DocumentSymbol
		container.range = common.get_token_range(impl^, ast_context.file.src)
		container.selectionRange = common.get_token_range(impl.type_expr, ast_context.file.src)
		ensure_selection_range_contained(&container.range, container.selectionRange)
		container.kind = .Struct

		if type_ident, ti_ok := impl.type_expr.derived.(^ast.Ident); ti_ok {
			container.name = type_ident.name
		} else {
			container.name = "impl"
		}

		children := make([dynamic]DocumentSymbol, context.temp_allocator)
		for m in impl.methods {
			if method, m_ok := make_method_document_symbol(m, ast_context.file.src); m_ok {
				append(&children, method)
			}
		}
		container.children = children[:]

		append(&symbols, container)
	}


	return symbols[:]
}

// Methodin: build a `.Method` DocumentSymbol from an in-struct/impl method
// decl (`name :: proc(...) {...}` or `name :: proc { ... }`). Mirrors the
// name extraction in collector.odin's register_in_struct_method.
@(private = "file")
make_method_document_symbol :: proc(method_stmt: ^ast.Stmt, src: string) -> (symbol: DocumentSymbol, ok: bool) {
	vd, vd_ok := method_stmt.derived.(^ast.Value_Decl)
	if !vd_ok || len(vd.names) != 1 {
		return {}, false
	}

	name_ident, ni_ok := vd.names[0].derived.(^ast.Ident)
	if !ni_ok {
		return {}, false
	}

	symbol.range = common.get_token_range(name_ident^, src)
	symbol.selectionRange = symbol.range
	symbol.name = name_ident.name
	symbol.kind = .Method
	return symbol, true
}

@(private="file")
ensure_selection_range_contained :: proc(range: ^common.Range, selection_range: common.Range) {
	// selection range must be contained with range, so we set the range start to be the selection range start
	range.start = selection_range.start

	// if the range end is somehow before the selection_range end, we set it to the end of the selection range
	if range.end.line < selection_range.end.line {
		range.end = selection_range.end
	} else if range.end.line == selection_range.end.line && range.end.character < selection_range.end.character {
		range.end = selection_range.end
	}
}
