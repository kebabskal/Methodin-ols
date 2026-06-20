package tests

import "core:testing"

import test "src:testing"

// A local package whose symbols we reference only from inside method bodies.
@(private = "file")
METHODIN_PKG :: test.Package {
	pkg    = "my_package",
	source = `package my_package
		do_thing :: proc() {}
	`,
}

// Control: a local package that is never referenced must be reported as unused.
// (Guards against the regression tests below passing for the wrong reason.)
@(test)
unused_import_control_is_reported :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		import "my_package"

		main :: proc() {}
		`,
		packages = {METHODIN_PKG},
	}

	test.expect_unused_imports(t, &source, {"my_package"})
}

// Methodin: an import referenced only inside an in-struct method
// (`name :: proc(...) {...}`) must not be reported as unused.
@(test)
import_used_only_in_in_struct_method_is_not_unused :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		import "my_package"

		Foo :: struct {
			run :: proc() {
				my_package.do_thing()
			},
		}

		main :: proc() {}
		`,
		packages = {METHODIN_PKG},
	}

	test.expect_unused_imports(t, &source, {})
}

// A local package providing a free proc whose first parameter is a fixed array,
// reachable as a UFCS method (`v.scale()`).
@(private = "file")
ARRAY_METHOD_PKG :: test.Package {
	pkg    = "vecmath",
	source = `package vecmath
		scale :: proc(v: [3]f32, k: f32) -> [3]f32 { return v * k }
	`,
}

// Methodin: an import referenced only via a UFCS method call on an array
// receiver (`v.scale()`, resolving to vecmath.scale) must not be reported as
// unused — mirrors the compiler's import-use tracking for the in-scope tier.
@(test)
import_used_only_via_ufcs_method_is_not_unused :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		import "vecmath"

		main :: proc() {
			v := [3]f32{1, 2, 3}
			_ = v.scale(2)
		}
		`,
		packages = {ARRAY_METHOD_PKG},
	}

	test.expect_unused_imports(t, &source, {})
}

// Methodin: the same UFCS array-method call, but on a struct *field* reached
// through the implicit `using self` inside an in-struct method body (the
// projectile.odin shape). The field's `self` scope must be established during
// the unused-import walk so `velocity` resolves and the import counts as used.
@(test)
import_used_only_via_ufcs_method_on_field_is_not_unused :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		import "vecmath"

		vec3 :: [3]f32

		Projectile :: struct {
			velocity: vec3,
			update :: proc() {
				_ = velocity.scale(2)
			},
		}

		main :: proc() {}
		`,
		packages = {ARRAY_METHOD_PKG},
	}

	test.expect_unused_imports(t, &source, {})
}

// Methodin: an import referenced only inside an `impl Type { ... }` method must
// not be reported as unused.
@(test)
import_used_only_in_impl_method_is_not_unused :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test
		import "my_package"

		Foo :: struct {
			x: int,
		}

		impl Foo {
			run :: proc() {
				my_package.do_thing()
			}
		}

		main :: proc() {}
		`,
		packages = {METHODIN_PKG},
	}

	test.expect_unused_imports(t, &source, {})
}
