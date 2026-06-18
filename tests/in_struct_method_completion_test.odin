package tests

import "core:testing"

import test "src:testing"

// Methodin: inside an in-struct method body the struct's own fields are in
// scope via an implicit `using self: ^Struct`. Bare-identifier completion must
// therefore offer the struct's fields.
@(test)
in_struct_method_bare_field_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		Controls :: struct {
			move_left:     int,
			previous_seed: int,

			init :: proc() {
				prev{*}
			},
		}
		`,
		packages = {},
	}

	test.expect_completion_labels(t, &source, "", {"previous_seed"})
}

// `self.` inside an in-struct method lists the struct's fields.
@(test)
in_struct_method_self_selector_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		Controls :: struct {
			move_left:     int,
			previous_seed: int,

			init :: proc() {
				self.{*}
			},
		}
		`,
		packages = {},
	}

	test.expect_completion_labels(t, &source, ".", {"move_left", "previous_seed"})
}

// A field that is itself a struct resolves through the implicit self, so chained
// member completion (`field.<member>`) works inside the method body.
@(test)
in_struct_method_chained_field_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		Control :: struct {
			is_down:     bool,
			was_pressed: bool,
		}
		Controls :: struct {
			move_left: Control,

			update :: proc() {
				move_left.{*}
			},
		}
		`,
		packages = {},
	}

	test.expect_completion_labels(t, &source, ".", {"is_down", "was_pressed"})
}
