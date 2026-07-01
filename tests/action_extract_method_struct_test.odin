package tests

import "core:strings"
import "core:testing"

import "src:common"
import server "src:server"

import test "src:testing"

// Methodin: extracting statements from an in-struct method should create a new
// in-struct method. `self` fields (frame) stay reachable via `using self` and
// are NOT captured; a local (x) IS captured as a parameter.
@(test)
extract_to_struct_method :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
World :: struct {
	frame: int,
	tick :: proc() {
		x: int = 10
		frame += x
		frame *= 2
	},
}
`,
		config = {enable_code_action_extract_method = true, enable_fake_method = true},
	}
	range := common.Range {
		start = {line = 5, character = 2},
		end   = {line = 6, character = 12},
	}

	check :: proc(t: ^testing.T, edits: []server.TextEdit) {
		testing.expect(t, len(edits) == 2, "expected 2 edits (method + call)")
		method_ok, call_ok := false, false
		for e in edits {
			if strings.contains(e.newText, "new_method :: proc(x: int)") &&
			   strings.contains(e.newText, "frame += x") &&
			   strings.contains(e.newText, "frame *= 2") {
				method_ok = true
			}
			if strings.contains(e.newText, "new_method(x)") {
				call_ok = true
			}
		}
		testing.expect(t, method_ok, "new in-struct method missing/incorrect (self field wrongly captured?)")
		testing.expect(t, call_ok, "call replacement missing")
	}

	test.expect_action_edits(t, &source, range, "Extract to method", check)
}
