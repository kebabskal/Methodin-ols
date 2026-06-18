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
