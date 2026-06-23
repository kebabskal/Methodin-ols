package tests

import "core:testing"

import test "src:testing"

// Methodin: methods declared in the *current* document (not just an already
// indexed package) must complete. The open document is now collected into the
// index on refresh, so `x.<method>` offers the struct's own methods.
@(test)
methodin_selector_method_current_file :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Rect :: struct {
			w: int,
			draw :: proc() {},
		}
		main :: proc() {
			r: Rect
			r.{*}
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_completion_labels(t, &source, ".", {"draw"})
}

// Inside an in-struct method body a sibling method is callable bare (the
// compiler rewrites `foo()` to `self.foo()`), so bare-identifier completion
// must offer the enclosing struct's methods.
@(test)
methodin_bare_sibling_method_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Rect :: struct {
			draw :: proc() {},
			redraw :: proc() {
				dr{*}
			},
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_completion_labels(t, &source, "", {"draw"})
}

// `self.` inside an in-struct method body lists the struct's methods (the
// receiver resolves to the named struct, whose methods are name-keyed).
@(test)
methodin_self_selector_method_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Rect :: struct {
			draw :: proc() {},
			redraw :: proc() {
				self.{*}
			},
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_completion_labels(t, &source, ".", {"draw"})
}

// `auto_union(T)` values promote the base type's methods for completion.
@(test)
methodin_auto_union_base_method_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Entity :: struct {
			hp: int,
			hit :: proc() {},
		}
		Enemy :: struct { using e: Entity }
		BaseEntity :: auto_union(Entity)
		main :: proc() {
			b: BaseEntity
			b.{*}
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_completion_labels(t, &source, ".", {"hit"})
}
