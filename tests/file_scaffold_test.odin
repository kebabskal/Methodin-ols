package tests

import "core:strings"
import "core:testing"

import server "src:server"

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
