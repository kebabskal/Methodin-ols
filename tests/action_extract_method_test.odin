package tests

import "core:strings"
import "core:testing"

import "src:common"
import server "src:server"

import test "src:testing"

// Selecting two statements that read the proc params `a` and `b` should extract
// them into a new proc with `a`/`b` as parameters, and replace the selection
// with a call passing them.
@(test)
extract_method_captures_params :: proc(t: ^testing.T) {
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

	check :: proc(t: ^testing.T, edits: []server.TextEdit) {
		joined := strings.builder_make(context.temp_allocator)
		for e in edits {
			strings.write_string(&joined, e.newText)
			strings.write_string(&joined, "\n----\n")
		}
		all := strings.to_string(joined)
		testing.expectf(t, strings.contains(all, "extracted_method :: proc(a: int, b: int) {"), "proc signature wrong:\n%s", all)
		testing.expectf(t, strings.contains(all, "c := a + b"), "body missing statement:\n%s", all)
		testing.expectf(t, strings.contains(all, "helper(c)"), "body missing statement:\n%s", all)
		testing.expectf(t, strings.contains(all, "extracted_method(a, b)"), "call missing:\n%s", all)
	}

	test.expect_action_edits(t, &source, range, "Extract method", check)
}
