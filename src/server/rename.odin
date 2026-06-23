package server

import "base:runtime"

import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:strings"

import "src:common"

get_rename :: proc(document: ^Document, new_text: string, position: common.Position) -> (WorkspaceEdit, bool) {
	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
		context.temp_allocator,
	)

	position_context, ok := get_document_position_context(document, position, .Hover)
	if !ok {
		log.warn("Failed to get position context")
		return {}, false
	}
	ast_context.position_hint = position_context.hint
	ast_context.current_package = ast_context.document_package

	get_globals(document.ast, &ast_context)
	get_locals(&ast_context, &position_context)

	locations, ok2 := resolve_references(document, &ast_context, &position_context)

	changes := make(map[string][dynamic]TextEdit, 0, context.temp_allocator)

	for location in locations {
		edits: ^[dynamic]TextEdit

		if edits = &changes[location.uri]; edits == nil {
			changes[strings.clone(location.uri, context.temp_allocator)] = make(
				[dynamic]TextEdit,
				context.temp_allocator,
			)
			edits = &changes[location.uri]
		}

		append(edits, TextEdit{newText = new_text, range = location.range})
	}

	workspace: WorkspaceEdit

	workspace.changes = make(map[string][]TextEdit, len(changes), context.temp_allocator)

	for k, v in changes {
		workspace.changes[k] = v[:]
	}

	return workspace, true
}


get_prepare_rename :: proc(document: ^Document, position: common.Position) -> (common.Range, bool) {
	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
		context.temp_allocator,
	)

	position_context, ok := get_document_position_context(document, position, .Hover)
	if !ok {
		log.warn("Failed to get position context")
		return {}, false
	}
	ast_context.position_hint = position_context.hint
	ast_context.current_package = ast_context.document_package

	get_globals(document.ast, &ast_context)
	get_locals(&ast_context, &position_context)

	symbol, ok2 := prepare_rename(document, &ast_context, &position_context)
	return symbol.range, ok2
}

get_struct_field_type_position :: proc(
	ast_context: ^AstContext, position_context: ^DocumentPositionContext, node: ^ast.Expr
) -> (Symbol, bool) {
	#partial switch v in node.derived {
	case ^ast.Ident:
		symbol := Symbol {
			range = common.get_token_range(node, ast_context.file.src),
		}
		return symbol, true
	case ^ast.Selector_Expr:
		symbol := Symbol {
			range = common.get_token_range(v.field, ast_context.file.src),
		}
		return symbol, true
	case ^ast.Pointer_Type:
		return get_struct_field_type_position(ast_context, position_context, v.elem)
	}
	return {}, false
}

// For preparing the rename, we want to position of the token within the current file,
// not the position of the declaration
prepare_rename :: proc(
	document: ^Document,
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	symbol: Symbol,
	ok: bool,
) {
	// Container declarations (struct/enum/union/bitset) are resolved before the
	// generic identifier branch because a field/variant name is itself an Ident.
	// On a miss they must FALL THROUGH to the identifier branch rather than
	// returning false -- otherwise, with Methodin, a cursor inside an in-struct
	// method body has `struct_type` set (the body lives inside the struct node),
	// the struct loop finds no matching field, and rename is rejected with
	// "that element can't be renamed" even for ordinary locals. This mirrors the
	// ordering already used by `prepare_references`.
	if position_context.struct_type != nil {
		for field in position_context.struct_type.fields.list {
			for name in field.names {
				if position_in_node(name, position_context.position) {
					symbol = Symbol {
						range = common.get_token_range(name, ast_context.file.src),
					}
					return symbol, true
				}
			}
			if position_in_node(field.type, position_context.position) {
				node := get_desired_expr(field.type, position_context.position)
				return get_struct_field_type_position(ast_context, position_context, node)
			}
		}
		// Methodin: allow prepareRename on an in-struct method's declaration name.
		for m in position_context.struct_type.methods {
			vd, vd_ok := m.derived.(^ast.Value_Decl)
			if !vd_ok || len(vd.names) != 1 {
				continue
			}
			if position_in_node(vd.names[0], position_context.position) {
				symbol = Symbol {
					range = common.get_token_range(vd.names[0], ast_context.file.src),
				}
				return symbol, true
			}
		}
	}

	// Methodin: allow prepareRename on an `impl <Type> { ... }` method's name.
	if position_context.impl_block != nil {
		for m in position_context.impl_block.methods {
			vd, vd_ok := m.derived.(^ast.Value_Decl)
			if !vd_ok || len(vd.names) != 1 {
				continue
			}
			if position_in_node(vd.names[0], position_context.position) {
				symbol = Symbol {
					range = common.get_token_range(vd.names[0], ast_context.file.src),
				}
				return symbol, true
			}
		}
	}

	if position_context.enum_type != nil {
		for field in position_context.enum_type.fields {
			if ident, ok := field.derived.(^ast.Ident); ok {
				if position_in_node(ident, position_context.position) {
					symbol = Symbol {
						range = common.get_token_range(ident, ast_context.file.src),
					}
					return symbol, true
				}
			} else if value, ok := field.derived.(^ast.Field_Value); ok {
				if position_in_node(value.field, position_context.position) {
					symbol = Symbol {
						range = common.get_token_range(value.field, ast_context.file.src),
					}
					return symbol, true
				} else if position_in_node(value.value, position_context.position) {
					symbol = Symbol {
						range = common.get_token_range(value.value, ast_context.file.src),
					}
					return symbol, true
				}
			}
		}
	}

	if position_context.bitset_type != nil {
		if position_in_node(position_context.bitset_type.elem, position_context.position) {
			symbol = Symbol {
				range = common.get_token_range(position_context.bitset_type.elem, ast_context.file.src),
			}
			return symbol, true
		}
	}

	if position_context.union_type != nil {
		for variant in position_context.union_type.variants {
			if position_in_node(variant, position_context.position) {
				symbol = Symbol {
					range = common.get_token_range(variant, ast_context.file.src),
				}
				return symbol, true
			}
		}
	}

	if position_context.implicit {
		range := common.get_token_range(position_context.implicit_selector_expr, ast_context.file.src)
		// Skip the `.`
		range.start.character += 1
		symbol = Symbol {
			range = range,
		}
		return symbol, true
	}

	if position_context.field_value != nil &&
	   position_context.comp_lit != nil &&
	   !is_expr_basic_lit(position_context.field_value.field) &&
	   position_in_node(position_context.field_value.field, position_context.position) {
		symbol = Symbol {
			range = common.get_token_range(position_context.field_value.field, ast_context.file.src),
		}
		return symbol, true
	}

	if position_context.selector_expr != nil {
		if position_in_node(position_context.selector, position_context.position) &&
		   position_context.identifier != nil {
			ident := position_context.identifier.derived.(^ast.Ident)
			return resolve_location_identifier(ast_context, ident^)
		}
		symbol, ok = resolve_location_selector(ast_context, position_context.selector_expr)
		if selector, ok := position_context.selector_expr.derived.(^ast.Selector_Expr); ok {
			symbol.range = common.get_token_range(selector.field.expr_base, ast_context.file.src)
		}
		return symbol, true
	}

	if position_context.identifier != nil {
		symbol = Symbol {
			range = common.get_token_range(position_context.identifier^, ast_context.file.src),
		}
		return symbol, true
	}

	return {}, false
}
