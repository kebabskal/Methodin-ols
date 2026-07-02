package tests

import "core:strings"
import "core:testing"

import "src:common"
import server "src:server"

import test "src:testing"

// "Extract proc to new file" should create a sibling file in the package
// containing the extracted proc, and replace the selection with a call. The
// edits are carried as documentChanges (create-file + text edits), not `changes`.
@(test)
extract_proc_to_new_file :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

helper :: proc(v: int) {}

run :: proc(a: int, b: int) {
	c := a + b
	helper(c)
}
`,
		config = {enable_code_action_extract_method = true},
	}
	range := common.Range {
		start = {line = 5, character = 0},
		end   = {line = 6, character = 10},
	}

	check :: proc(t: ^testing.T, changes: []server.DocumentChange) {
		testing.expectf(
			t,
			len(changes) == 3,
			"expected 3 documentChanges (create + fill + call), got %d",
			len(changes),
		)
		saw_create, saw_proc, saw_call := false, false, false
		for ch in changes {
			#partial switch c in ch {
			case server.CreateFile:
				if c.kind == "create" && strings.has_suffix(c.uri, "extracted_proc.odin") {
					saw_create = true
				}
			case server.TextDocumentEdit:
				for e in c.edits {
					if strings.contains(e.newText, "package test") &&
					   strings.contains(e.newText, "extracted_proc :: proc(a: int, b: int) {") &&
					   strings.contains(e.newText, "c := a + b") {
						saw_proc = true
					}
					if strings.contains(e.newText, "extracted_proc(a, b)") {
						saw_call = true
					}
				}
			}
		}
		testing.expect(t, saw_create, "missing create-file for extracted_proc.odin")
		testing.expect(t, saw_proc, "new file missing package/proc content")
		testing.expect(t, saw_call, "original file missing call replacement")
	}

	test.expect_action_document_changes(t, &source, range, "Extract proc to new file", check)
}
