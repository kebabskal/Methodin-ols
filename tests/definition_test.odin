package tests

import "core:fmt"
import "core:testing"

import "src:common"

import test "src:testing"

@(test)
ast_goto_bit_set_comp_literal :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		TestEnum :: enum {
			valueOne,
			valueTwo,
		}
		
		EnumIndexedArray :: [TestEnum]u32 {
			.value{*}One = 1,
			.valueTwo = 2,
		}
		`,
	}

	location := common.Location {
		range = {start = {line = 2, character = 3}, end = {line = 2, character = 11}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_bit_set_index_enumerated_array :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		TestEnum :: enum {
			valueOne,
			valueTwo,
		}

		EnumIndexedArray :: [TestEnum]u32 {
			.valueOne = 1,
			.valueTwo = 2,
		}

		my_proc :: proc() -> u32 {
			arr :: EnumIndexedArray
			return arr[.valueO{*}ne]
		}
		`,
	}

	location := common.Location {
		range = {start = {line = 2, character = 3}, end = {line = 2, character = 11}},
	}

	test.expect_definition_locations(t, &source, {location})
}


@(test)
ast_goto_comp_lit_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
        Point :: struct {
            x, y, z : f32,
        }

        main :: proc() {
            point := Point {
                x{*} = 2, y = 5, z = 0,
            }
        }
		`,
	}

	location := common.Location {
		range = {start = {line = 2, character = 12}, end = {line = 2, character = 13}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_struct_definition :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
        Point :: struct {
            x, y, z : f32,
        }

        main :: proc() {
            point := Po{*}int {
                x = 2, y = 5, z = 0,
            }
        }
		`,
	}

	location := common.Location {
		range = {start = {line = 1, character = 8}, end = {line = 1, character = 13}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_comp_lit_field_indexed :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
        Point :: struct {
            x, y, z : f32,
        }

        main :: proc() {
            point := [2]Point {
                {x{*} = 2, y = 5, z = 0},
                {y = 10, y = 20, z = 10},
            }
        }
		`,
	}

	location := common.Location {
		range = {start = {line = 2, character = 12}, end = {line = 2, character = 13}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_untyped_comp_lit_in_proc :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
			My_Struct :: struct {
				one: int,
				two: int,
			}

			my_function :: proc(my_struct: My_Struct) {

			}

			main :: proc() {
				my_function({on{*}e = 2, two = 3})
			}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 2, character = 4}, end = {line = 2, character = 7}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_bit_field_definition :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
			My_Bit_Field :: bit_field uint {
				one: int | 1,
				two: int | 1,
			}

			main :: proc() {
				it: My_B{*}it_Field
			}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 1, character = 3}, end = {line = 1, character = 15}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_bit_field_field_definition :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
			My_Bit_Field :: bit_field uint {
				one: int | 1,
				two: int | 1,
			}

			main :: proc() {
				it: My_Bit_Field
				it.on{*}e
			}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 2, character = 4}, end = {line = 2, character = 7}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_bit_field_field_in_proc :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
			My_Struct :: bit_field uint {
				one: int | 1,
				two: int | 2,
			}

			my_function :: proc(my_struct: My_Struct) {

			}

			main :: proc() {
				my_function({on{*}e = 2, two = 3})
			}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 2, character = 4}, end = {line = 2, character = 7}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_shadowed_value_decls :: proc(t: ^testing.T) {
	source0 := test.Source {
		main     = `package test
			main :: proc() {
				foo := 1
				
				{
					fo{*}o := 2
				}
			}
		`,
		packages = {},
	}
	test.expect_definition_locations(t, &source0, {{range = {{line = 5, character = 5}, {line = 5, character = 8}}}})

	source1 := test.Source {
		main     = `package test
			main :: proc() {
				foo := 1
				
				{
					foo := 2
					fo{*}o
				}
			}
		`,
		packages = {},
	}
	test.expect_definition_locations(t, &source1, {{range = {{line = 5, character = 5}, {line = 5, character = 8}}}})

	source3 := test.Source {
		main     = `package test
			main :: proc() {
				foo := 1
				
				{
					foo := fo{*}o
				}
			}
		`,
		packages = {},
	}
	test.expect_definition_locations(t, &source3, {{range = {{line = 2, character = 4}, {line = 2, character = 7}}}})
}

@(test)
ast_goto_implicit_super_enum_infer_from_assignment :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
		Sub_Enum1 :: enum {
			ONE,
		}
		Sub_Enum2 :: enum {
			TWO,
		}

		Super_Enum :: union {
			Sub_Enum1,
			Sub_Enum2,
		}

		main :: proc() {
			my_enum: Super_Enum
			my_enum = .ON{*}E
		}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 2, character = 3}, end = {line = 2, character = 6}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_implicit_enum_infer_from_assignment :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
		My_Enum :: enum {
			One,
			Two,
			Three,
			Four,
		}

		my_function :: proc() {
			my_enum: My_Enum
			my_enum = .Fo{*}ur
		}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 5, character = 3}, end = {line = 5, character = 7}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_implicit_enum_infer_from_return :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
		My_Enum :: enum {
			One,
			Two,
			Three,
			Four,
		}

		my_function :: proc() -> My_Enum {
			return .Fo{*}ur
		}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 5, character = 3}, end = {line = 5, character = 7}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_implicit_enum_infer_from_function :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test	
		My_Enum :: enum {
			One,
			Two,
			Three,
			Four,
		}

		my_fn :: proc(my_enum: My_Enum) {

		}

		my_function :: proc() {
			my_fn(.Fo{*}ur)
		}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 5, character = 3}, end = {line = 5, character = 7}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_implicit_enum_infer_from_assignment_within_switch :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		Bar :: enum {
			Bar1,
			Bar2,
		}

		Foo :: enum {
			Foo1,
			Foo2,
		}


		main :: proc() {
			my_foo: Foo
			my_bar: Bar
			switch my_foo {
			case .Foo1:
				my_bar = .B{*}ar2
			case .Foo2:
				my_bar = .Bar1
			}
		}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 3, character = 3}, end = {line = 3, character = 7}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_variable_declaration_with_selector_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Bar :: struct {
			foo: int,
		}

		main :: proc() {
			bar: [1]Bar
			b{*}ar[0].foo = 5
		}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 7, character = 3}, end = {line = 7, character = 6}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_variable_field_definition_with_selector_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Bar :: struct {
			foo: int,
		}

		main :: proc() {
			bar: [1]Bar
			bar[0].fo{*}o = 5
		}
		`,
		packages = {},
	}

	location := common.Location {
		range = {start = {line = 3, character = 3}, end = {line = 3, character = 6}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_struct_definition_with_empty_line_at_top_of_file :: proc(t: ^testing.T) {
	source := test.Source {
		main = `
		package test

		Foo :: struct {
			bar: int,
		}

		main :: proc() {
			foo := F{*}oo{}
		}
		`,
	}

	location := common.Location {
		range = {start = {line = 3, character = 2}, end = {line = 3, character = 5}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_enum_from_map_key :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

		Foo :: enum {
			A,
			B,
		}

		main :: proc() {
			m: map[Foo]int
			m[.A{*}] = 2
		}
		`,
	}

	location := common.Location {
		range = {start = {line = 3, character = 3}, end = {line = 3, character = 4}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_struct_field_from_proc :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Bar :: struct {
			bar: int,
		}

		foo :: proc() -> Bar {
			return Bar{}
		}

		main :: proc() {
			bar := foo().b{*}ar
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 3, character = 3}, end = {line = 3, character = 6}}},
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_proc_named_param :: proc (t: ^testing.T) {
	source := test.Source {
		main     = `package test

		foo :: proc(a: int) {}

		main :: proc() {
			a := "hellope"
			foo(a{*} = 0)
		}
		`,
	}

	locations := []common.Location {
		{range = {start = {line = 2, character = 14}, end = {line = 2, character = 15}}},
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_param_inside_where_clause :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		foo :: proc(x: [2]int)
			where len(x) > 1,
				  type_of(x{*}) == [2]int {
		}
	`,
	}
	locations := []common.Location {
		{range = {start = {line = 1, character = 14}, end = {line = 1, character = 15}}},
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_enum_struct_field_without_name :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			A,
			B,
		}

		Bar :: struct {
			foo: Foo,
		}

		main :: proc() {
			bar: Bar = {.A{*}}
		}
	`,
	}
	locations := []common.Location {
		{range = {start = {line = 2, character = 3}, end = {line = 2, character = 4}}},
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_soa_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			x, y: int,
		}

		main :: proc() {
			foos: #soa[]Foo
			x := foos.x{*}
		}
	`,
	}
	locations := []common.Location {
		{range = {start = {line = 2, character = 3}, end = {line = 2, character = 4}}},
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_nested_using_bit_field_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			a: int,
			using _: bit_field u8 {
				b: u8 | 4
			}
		}

		main :: proc() {
			foo: Foo
			b := foo.b{*}
		}
	`,
	}
	locations := []common.Location {
		{range = {start = {line = 4, character = 4}, end = {line = 4, character = 5}}},
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_nested_using_struct_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: struct {
			a: int,
			using _: struct {
				b: u8
			}
		}

		main :: proc() {
			foo: Foo
			b := foo.b{*}
		}
	`,
	}
	locations := []common.Location {
		{range = {start = {line = 4, character = 4}, end = {line = 4, character = 5}}},
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_package_declaration :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package
			Bar :: struct{}
		`})
	source := test.Source {
		main = `package test
		import "my_package"

		main :: proc() {
			bar: m{*}y_package.Bar
		}
	`,
		packages = packages[:],
	}
	locations := []common.Location {
		{range = {start = {line = 1, character = 9}, end = {line = 1, character = 21}}},
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_package_declaration_with_alias :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package
			Bar :: struct{}
		`})
	source := test.Source {
		main = `package test
		import mp "my_package"

		main :: proc() {
			bar: m{*}p.Bar
		}
	`,
		packages = packages[:],
	}
	locations := []common.Location {
		{range = {start = {line = 1, character = 9}, end = {line = 1, character = 11}}},
	}

	test.expect_definition_locations(t, &source, locations[:])
}
@(test)
ast_goto_proc_group_overload_with_selector :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)

	append(&packages, test.Package{pkg = "my_package", source = `package my_package
			push_back :: proc(arr: ^[dynamic]int, val: int) {}
			push_back_elems :: proc(arr: ^[dynamic]int, vals: ..int) {}
			append :: proc{push_back, push_back_elems}
		`})
	source := test.Source {
		main = `package test
		import mp "my_package"

		main :: proc() {
			arr: [dynamic]int
			mp.app{*}end(&arr, 1)
		}
	`,
		packages = packages[:],
		config = {enable_overload_resolution = true},
	}
	// Should go to push_back (line 1, character 3) instead of append (line 3)
	// because push_back is the overload being used with a single value argument
	locations := []common.Location {
		{range = {start = {line = 1, character = 3}, end = {line = 1, character = 12}}},
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_proc_group_overload_identifier :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		push_back :: proc(arr: ^[dynamic]int, val: int) {}
		push_back_elems :: proc(arr: ^[dynamic]int, vals: ..int) {}
		append :: proc{push_back, push_back_elems}

		main :: proc() {
			arr: [dynamic]int
			app{*}end(&arr, 1)
		}
	`,
		config = {enable_overload_resolution = true},
	}
	// Should go to push_back (line 1, character 2) instead of append (line 3)
	// because push_back is the overload being used with a single value argument
	locations := []common.Location {
		{range = {start = {line = 1, character = 2}, end = {line = 1, character = 11}}},
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_fixed_cap_dyn_array_capacity :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: 5

		Bar :: [dynamic; Fo{*}o]int
	`,
	}
	locations := []common.Location {
		{range = {start = {line = 1, character = 2}, end = {line = 1, character = 5}}},
	}

	test.expect_definition_locations(t, &source, locations[:])
}

@(test)
ast_goto_enum_field_value_reference :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Foo :: enum {
			Bar,
			Baz = B{*}ar,
		}
		`,
	}

	location := common.Location {
		range = {start = {line = 2, character = 3}, end = {line = 2, character = 6}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_ufcs_method_on_struct :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)
	append(&packages, test.Package{pkg = "game", source = `package game
		Player :: struct { hp: int }
		damage :: proc(p: ^Player, amount: int) { p.hp -= amount }
	`})
	source := test.Source {
		main = `package test
		import "game"
		main :: proc() {
			player: game.Player
			player.d{*}amage(10)
		}
		`,
		packages = packages[:],
	}

	// damage proc at line 2 of the game package source (the file itself
	// indents the raw string with 2 tabs, so character 2 = identifier start).
	location := common.Location {
		range = {start = {line = 2, character = 2}, end = {line = 2, character = 8}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_ufcs_method_on_builtin_int :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)
	append(&packages, test.Package{pkg = "math", source = `package math
		double :: proc(x: int) -> int { return x * 2 }
	`})
	source := test.Source {
		main = `package test
		import "math"
		main :: proc() {
			n: int = 7
			n.d{*}ouble()
		}
		`,
		packages = packages[:],
	}

	location := common.Location {
		range = {start = {line = 1, character = 2}, end = {line = 1, character = 8}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_ufcs_method_through_using_field_in_other_package :: proc(t: ^testing.T) {
	// Cross-package using-walk: `Body` and `apply_force` live in the
	// `physics` package; `Entity` in `test` embeds `physics.Body` with
	// `using`. UFCS must walk the `using` field into the physics package
	// to resolve `e.apply_force`.
	packages := make([dynamic]test.Package, context.temp_allocator)
	append(&packages, test.Package{pkg = "physics", source = `package physics
		Body :: struct { x, y: f32 }
		apply_force :: proc(b: ^Body, fx, fy: f32) { b.x += fx; b.y += fy }
	`})
	source := test.Source {
		main = `package test
		import "physics"
		Entity :: struct {
			using body: physics.Body,
			name: string,
		}
		main :: proc() {
			e: Entity
			e.a{*}pply_force(1, 2)
		}
		`,
		packages = packages[:],
	}

	location := common.Location {
		range = {start = {line = 2, character = 2}, end = {line = 2, character = 13}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_in_struct_method :: proc(t: ^testing.T) {
	// `name :: proc(...)` declared inside the struct body should be
	// reachable via UFCS like a free proc keyed by the receiver type.
	// Lives in a sub-package because OLS only indexes packages in the
	// test harness.
	packages := make([dynamic]test.Package, context.temp_allocator)
	append(&packages, test.Package{pkg = "game", source = `package game
		Player :: struct {
			hp: int,
			damage :: proc(amount: int) {
				hp -= amount
			},
		}
	`})
	source := test.Source {
		main = `package test
		import "game"
		main :: proc() {
			p: game.Player
			p.da{*}mage(10)
		}
		`,
		packages = packages[:],
	}

	// `damage` ident is on line 3 of the game package source with 3
	// tabs of indent (one for the raw string, one for the struct,
	// one for the field list).
	location := common.Location {
		range = {start = {line = 3, character = 3}, end = {line = 3, character = 9}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_intra_struct_method_call :: proc(t: ^testing.T) {
	// Inside an in-struct method body, a bare-ident call to another
	// method on the same struct should resolve through UFCS the same
	// way an explicit `self.<method>(...)` would. OLS mirrors the
	// compiler's rewrite by walking the body AST and rewriting
	// matching Call_Expr callees into `self.<ident>`.
	packages := make([dynamic]test.Package, context.temp_allocator)
	append(&packages, test.Package{pkg = "world", source = `package world
		Animal :: struct {
			greet :: proc(name: string) {
				base_greet("Hi", name)
			},
			base_greet :: proc(greeting: string, name: string) {
			},
		}
	`})
	source := test.Source {
		main = `package test
		import "world"
		main :: proc() {
			a: world.Animal
			a.gr{*}eet("there")
		}
		`,
		packages = packages[:],
	}

	// goto-def from `a.greet` jumps to greet's declaration in world.
	location := common.Location {
		range = {start = {line = 2, character = 3}, end = {line = 2, character = 8}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_union_dispatch_method :: proc(t: ^testing.T) {
	// When every variant of a union has the same method, the compiler
	// synthesises a dispatcher at parse time. OLS mirrors that by
	// copying each variant's method into the union's bucket, so
	// `thing.greet(...)` on a value of type `Thing` resolves to one
	// of the variant methods (in this test, the first variant's).
	packages := make([dynamic]test.Package, context.temp_allocator)
	append(&packages, test.Package{pkg = "zoo", source = `package zoo
		Animal :: struct {
			greet :: proc(name: string) {
			},
		}
		Dog :: struct {
			greet :: proc(name: string) {
			},
		}
		Thing :: union { Animal, Dog }
	`})
	source := test.Source {
		main = `package test
		import "zoo"
		main :: proc() {
			t: zoo.Thing
			t.gr{*}eet("hi")
		}
		`,
		packages = packages[:],
	}

	// The dispatch lands on Animal's greet (the first variant).
	location := common.Location {
		range = {start = {line = 2, character = 3}, end = {line = 2, character = 8}},
	}

	test.expect_definition_locations(t, &source, {location})
}

@(test)
ast_goto_impl_block_method :: proc(t: ^testing.T) {
	// Same as in-struct, but the method is declared in a separate
	// `impl <Type> { ... }` block.
	packages := make([dynamic]test.Package, context.temp_allocator)
	append(&packages, test.Package{pkg = "geometry", source = `package geometry
		Box :: struct { w, h: int }
		impl Box {
			area :: proc() -> int {
				return w * h
			}
		}
	`})
	source := test.Source {
		main = `package test
		import "geometry"
		main :: proc() {
			b: geometry.Box
			b.ar{*}ea()
		}
		`,
		packages = packages[:],
	}

	location := common.Location {
		range = {start = {line = 3, character = 3}, end = {line = 3, character = 7}},
	}

	test.expect_definition_locations(t, &source, {location})
}
