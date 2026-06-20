package tests

import "core:testing"

import "src:common"

import test "src:testing"

// Methodin: a cursor inside an in-struct method body has `struct_type` set (the
// body lives inside the struct node), so `prepare_rename` used to reject every
// ordinary local with "that element can't be renamed". prepareRename must now
// fall through to the identifier branch and report the token's own range.
@(test)
prepare_rename_local_in_in_struct_method :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		P :: struct {
			update :: proc() {
				p_v{*}el := 1
				p_vel = p_vel + 1
			},
		}
		`,
	}
	range := common.Range{start = {line = 3, character = 4}, end = {line = 3, character = 9}}
	test.expect_prepare_rename_range(t, &source, range)
}

// Methodin: the same local must rename end-to-end inside an in-struct method
// body. Declaration + two uses = 3 edits.
@(test)
rename_local_in_in_struct_method :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		P :: struct {
			update :: proc() {
				p_v{*}el := 1
				p_vel = p_vel + 1
			},
		}
		`,
	}
	test.expect_rename_edit_count(t, &source, "speed", 3)
}

// Methodin: a local inside an `impl Type { ... }` method body must rename too.
@(test)
rename_local_in_impl_method :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Dog :: struct {
			name: int,
		}
		impl Dog {
			bark :: proc() {
				vol{*}ume := 1
				volume = volume + 1
			}
		}
		`,
	}
	test.expect_rename_edit_count(t, &source, "loudness", 3)
}

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
