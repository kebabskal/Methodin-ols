package tests

import "core:testing"

import test "src:testing"

// Methodin: renaming a struct field must reach uses inside an in-struct method
// body, where the field is accessed through the implicit `using self: ^Struct`.
// Declaration + two uses in update() = 3 edits.
@(test)
rename_field_used_in_in_struct_method :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Projectile :: struct {
			vel{*}ocity: int,
			update :: proc() {
				velocity = velocity + 1
			},
		}
		`,
	}
	test.expect_rename_edit_count(t, &source, "speed", 3)
}

// Methodin: the same, but the field is used inside an `impl Type { ... }` method
// body (also an implicit `using self: ^Type`).
@(test)
rename_field_used_in_impl_method :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Dog :: struct {
			na{*}me: int,
		}
		impl Dog {
			bark :: proc() {
				name = name + 1
			}
		}
		`,
	}
	test.expect_rename_edit_count(t, &source, "title", 3)
}
