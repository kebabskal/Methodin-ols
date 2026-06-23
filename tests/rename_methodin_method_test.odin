package tests

import "core:testing"

import test "src:testing"

// Methodin: renaming from a method's DECLARATION name renames the declaration
// and every call site. Declaration + one call = 2 edits.
@(test)
rename_method_from_declaration :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Rect :: struct {
			dr{*}aw :: proc() {},
		}
		main :: proc() {
			r: Rect
			r.draw()
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_rename_edit_count(t, &source, "render", 2)
}

// Renaming from a CALL SITE also reaches the declaration. Declaration + call = 2.
@(test)
rename_method_from_call_site :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Rect :: struct {
			draw :: proc() {},
		}
		main :: proc() {
			r: Rect
			r.dr{*}aw()
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_rename_edit_count(t, &source, "render", 2)
}

// A same-named method on a different struct must NOT be renamed: methods are
// keyed by receiver type, so `Rect.draw` and `Circle.draw` are distinct.
// Only Rect.draw's declaration + its one call = 2 (not 4).
@(test)
rename_method_no_cross_struct :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Rect :: struct {
			dr{*}aw :: proc() {},
		}
		Circle :: struct {
			draw :: proc() {},
		}
		main :: proc() {
			r: Rect
			r.draw()
			c: Circle
			c.draw()
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_rename_edit_count(t, &source, "render", 2)
}

// Multiple call sites all rename. Declaration + three calls = 4.
@(test)
rename_method_multiple_call_sites :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Rect :: struct {
			dr{*}aw :: proc() {},
		}
		main :: proc() {
			r: Rect
			r.draw()
			r.draw()
			r.draw()
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_rename_edit_count(t, &source, "render", 4)
}

// A method declared in an `impl <Type> { ... }` block renames from a call site.
// Declaration + call = 2.
@(test)
rename_impl_method_from_call_site :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Dog :: struct { name: int }
		impl Dog {
			bark :: proc() {}
		}
		main :: proc() {
			d: Dog
			d.ba{*}rk()
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_rename_edit_count(t, &source, "speak", 2)
}

// A bare sibling-method call inside another method body (the compiler rewrites
// `draw()` to `self.draw()`) renames too. Declaration + bare call = 2.
@(test)
rename_method_intra_body_bare_call :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Rect :: struct {
			dr{*}aw :: proc() {},
			redraw :: proc() {
				draw()
			},
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_rename_edit_count(t, &source, "render", 2)
}

// A method declared in an `impl <Type>` block renames from its DECLARATION name.
// Declaration + call = 2.
@(test)
rename_impl_method_from_declaration :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Dog :: struct { name: int }
		impl Dog {
			ba{*}rk :: proc() {}
		}
		main :: proc() {
			d: Dog
			d.bark()
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_rename_edit_count(t, &source, "speak", 2)
}
