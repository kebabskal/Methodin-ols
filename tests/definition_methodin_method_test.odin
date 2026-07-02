package tests

import "core:testing"

import "src:common"
import test "src:testing"

// Methodin: go-to-definition on a bare sibling method call (`spawn()` ==
// `self.spawn()`) must reach the method's declaration. Mirrors
// odin-daggers/world.odin:224 update_spawn_energy().
@(test)
definition_bare_sibling_method :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
World :: struct {
	frame: int,
	spawn :: proc() {},
	update :: proc() {
		spa{*}wn()
	},
}
`,
		config = {enable_fake_method = true},
	}
	location := common.Location {
		range = {start = {line = 3, character = 1}, end = {line = 3, character = 6}},
	}
	test.expect_definition_locations(t, &source, {location})
}

// The in-scope UFCS tier must validate the receiver against the candidate's
// first parameter: a struct-typed value must NOT resolve `s.println` to a
// same-named free proc that takes something else entirely. (The selector
// fallback reports the receiver type's own declaration instead — the
// important part is that it lands on My_Struct, not on utils.println.)
@(test)
ast_ufcs_in_scope_requires_receiver_match :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)
	append(&packages, test.Package{pkg = "utils", source = `package utils
		println :: proc(x: int) {
		}
	`})
	source := test.Source {
		main = `package test
		import "utils"
		My_Struct :: struct {
			hp: int,
		}
		main :: proc() {
			_ = utils.println
			s: My_Struct
			s.pri{*}ntln()
		}
		`,
		packages = packages[:],
	}

	// The receiver type's declaration in the main file.
	location := common.Location {
		range = {start = {line = 2, character = 15}, end = {line = 4, character = 3}},
	}

	test.expect_definition_locations(t, &source, {location})
}

// ...while a first parameter that does name the receiver type resolves.
@(test)
ast_ufcs_in_scope_receiver_match_resolves :: proc(t: ^testing.T) {
	packages := make([dynamic]test.Package, context.temp_allocator)
	append(&packages, test.Package{pkg = "world", source = `package world
		World :: struct {
			frame: int,
		}
		advance :: proc(w: ^World, steps: int) {
		}
	`})
	source := test.Source {
		main = `package test
		import "world"
		main :: proc() {
			w: world.World
			w.adv{*}ance(1)
		}
		`,
		packages = packages[:],
	}

	// advance's declaration in world.
	location := common.Location {
		range = {start = {line = 4, character = 2}, end = {line = 4, character = 9}},
	}

	test.expect_definition_locations(t, &source, {location})
}

// Goto-definition on a type-scoped constant lands on its declaration.
@(test)
definition_type_scoped_constant :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
Vec3 :: distinct [3]f32
impl Vec3 {
	UP :: Vec3{0, 1, 0},
}
main :: proc() {
	v := Vec3.U{*}P
	_ = v
}
`,
	}
	location := common.Location {
		range = {start = {line = 3, character = 1}, end = {line = 3, character = 3}},
	}
	test.expect_definition_locations(t, &source, {location})
}
