package tests

import "core:strings"
import "core:testing"

import "src:common"
import server "src:server"

import test "src:testing"

// Methodin: selecting `frame * 2 + 1` inside an in-struct method should offer
// "Extract to struct field" — add `new_field: int,` to the struct, assign it at
// the use site, and replace the expression with the bare field name.
@(test)
extract_field_from_binary_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
World :: struct {
	frame: int,
	tick :: proc() {
		x := frame * 2 + 1
	},
}
`,
		config = {enable_code_action_extract_variable = true, enable_fake_method = true},
	}
	// `frame * 2 + 1` on line 4 (0-based): 2 tabs + "x := " = 7, expr is 13 chars.
	range := common.Range {
		start = {line = 4, character = 7},
		end   = {line = 4, character = 20},
	}

	check :: proc(t: ^testing.T, edits: []server.TextEdit) {
		testing.expect(t, len(edits) == 3, "expected 3 edits (field + assign + replace)")
		field_found, assign_found, repl_found := false, false, false
		for e in edits {
			if strings.contains(e.newText, "new_field: int,") do field_found = true
			if strings.contains(e.newText, "new_field = frame * 2 + 1") do assign_found = true
			if e.newText == "new_field" do repl_found = true
		}
		testing.expect(t, field_found, "struct field edit missing/incorrect")
		testing.expect(t, assign_found, "assignment edit missing")
		testing.expect(t, repl_found, "replacement edit missing")
	}

	test.expect_action_edits(t, &source, range, "Extract to struct field", check)
}
