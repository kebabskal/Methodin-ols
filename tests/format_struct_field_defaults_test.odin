package tests

import "core:strings"
import "core:testing"

import test "src:testing"

// Methodin/odinfmt: struct fields with both a type and a default value
// (`health: f32 = 100.0`) must keep the default when formatted. The printer
// used to only emit defaults in the untyped `name := value` form, silently
// deleting the initializer from typed fields.

@(test)
format_keeps_struct_field_defaults :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

Player :: struct {
	health: f32 = 100.0,
	name:   string,
	scale:  [3]f32 = {1, 1, 1},
}
`,
		packages = {},
	}
	out := test.format_document_for_test(&source)
	testing.expect(t, strings.contains(out, "health: f32 = 100.0"), "typed field default was dropped")
	testing.expect(t, strings.contains(out, "scale:  [3]f32 = {1, 1, 1}"), "comp-lit field default was dropped")
	testing.expect(t, strings.contains(out, "name:   string"), "plain field mangled")
}

// Same, but inside a struct that also has in-struct methods — that body goes
// through visit_struct_body instead of visit_struct_field_list.
@(test)
format_keeps_struct_field_defaults_with_methods :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

Enemy :: struct {
	health: f32 = 100.0,

	update :: proc() {
		health -= 1
	},
}
`,
		packages = {},
	}
	out := test.format_document_for_test(&source)
	testing.expect(t, strings.contains(out, "health: f32 = 100.0"), "field default dropped in struct with methods")
}
