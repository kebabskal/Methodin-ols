package tests

import "core:strings"
import "core:testing"

import "src:common"
import server "src:server"

import test "src:testing"

// Selecting the `a + b * 2` expression should offer "Extract local variable",
// hoisting it into `new_variable := a + b * 2` above the statement and replacing
// the occurrence with `new_variable`.
@(test)
extract_variable_from_binary_expr :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

f :: proc(a: int, b: int) -> int {
	return a + b * 2
}
`,
		config = {enable_code_action_extract_variable = true},
	}
	// Range covering `a + b * 2` on line 3 (0-based), after "\treturn ".
	range := common.Range {
		start = {line = 3, character = 8},
		end   = {line = 3, character = 17},
	}

	check :: proc(t: ^testing.T, edits: []server.TextEdit) {
		testing.expect(t, len(edits) == 2, "expected 2 edits (decl + replacement)")
		decl_found := false
		repl_found := false
		for e in edits {
			if strings.contains(e.newText, "new_variable := a + b * 2") {
				decl_found = true
			}
			if e.newText == "new_variable" {
				repl_found = true
			}
		}
		testing.expect(t, decl_found, "declaration edit missing/incorrect")
		testing.expect(t, repl_found, "replacement edit missing")
	}

	test.expect_action_edits(t, &source, range, "Extract local variable", check)
}

// Extracting the call `compute(x)` in the middle of a larger expression.
@(test)
extract_variable_from_call :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

compute :: proc(x: int) -> int { return x }

f :: proc(x: int) -> int {
	return compute(x) + 1
}
`,
		config = {enable_code_action_extract_variable = true},
	}
	range := common.Range {
		start = {line = 5, character = 8},
		end   = {line = 5, character = 18},
	}

	check :: proc(t: ^testing.T, edits: []server.TextEdit) {
		testing.expect(t, len(edits) == 2, "expected 2 edits")
		ok := false
		for e in edits {
			if strings.contains(e.newText, "new_variable := compute(x)") {
				ok = true
			}
		}
		testing.expect(t, ok, "declaration edit missing/incorrect")
	}

	test.expect_action_edits(t, &source, range, "Extract local variable", check)
}
