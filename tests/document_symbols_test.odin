package tests

import "core:testing"

import test "src:testing"

@(test)
document_symbol_in_struct_method :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Foo :: struct {
			name: string,
			bar :: proc(self: ^Foo) {},
		}
		`,
		packages = {},
	}

	test.expect_document_symbol_names(t, &source, {"Foo", "name", "bar"})
}

@(test)
document_symbol_impl_block_method :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

		Foo :: struct {
			name: string,
		}

		impl Foo {
			baz :: proc(self: ^Foo) {},
		}
		`,
		packages = {},
	}

	test.expect_document_symbol_names(t, &source, {"Foo", "name", "baz"})
}
