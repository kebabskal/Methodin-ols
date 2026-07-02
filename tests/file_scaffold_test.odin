package tests

import "core:strings"
import "core:testing"

import server "src:server"
import test "src:testing"

// The scaffold builder derives `package <dir>` and a PascalCase struct from the
// file path (offered when a file has no package declaration).
@(test)
file_scaffold_names :: proc(t: ^testing.T) {
	doc := server.Document {
		fullpath = "workspace/odin-daggers/enemy_base.odin",
	}
	item, ok := server.build_file_scaffold_completion(&doc)
	testing.expect(t, ok, "scaffold should be offered")
	insert := item.insertText.? or_else ""
	testing.expect(t, strings.contains(insert, "package odin_daggers"), "package name from dir")
	testing.expect(t, strings.contains(insert, "EnemyBase :: struct"), "PascalCase struct from filename")
}

// A directory starting with a digit can't be used verbatim — identifiers
// can't start with a digit.
@(test)
file_scaffold_digit_dir :: proc(t: ^testing.T) {
	doc := server.Document {
		fullpath = "workspace/3d-models/mesh_loader.odin",
	}
	item, ok := server.build_file_scaffold_completion(&doc)
	testing.expect(t, ok, "scaffold should be offered")
	insert := item.insertText.? or_else ""
	testing.expect(t, strings.contains(insert, "package _3d_models"), "digit-leading dir gets _ prefix")
}

// A file with code but a missing/broken package line must not be hijacked by
// the scaffold item (accepting it would insert `package ...` mid-file). The
// file doesn't parse without a package line, so no labels are expected — the
// scaffold just must not be one of them.
@(test)
file_scaffold_not_offered_with_decls :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `
		my_variable := 3

		main :: proc() {
			my_var{*}
		}
		`,
		packages = {},
	}

	test.expect_completion_labels(t, &source, "", {}, {"package"})
}
