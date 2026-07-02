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

// Hoisting an expression out of an `if` would evaluate it above the guard
// that protects it — never offered for guarded statements.
@(test)
extract_variable_refuses_hoist_past_guard :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
run :: proc(p: ^int) {
	if p != nil do use(p^)
}
use :: proc(a: int) {}
`,
		config = {enable_code_action_extract_variable = true},
	}
	// select `p^` inside the guarded body
	range := common.Range {
		start = {line = 2, character = 19},
		end   = {line = 2, character = 21},
	}
	test.expect_action_not_offered(t, &source, range, "Extract local variable")
}

// Hoisting out of a loop condition turns per-iteration evaluation into
// once-before-the-loop.
@(test)
extract_variable_refuses_loop_header :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
run :: proc(a: int) {
	for next_value(a) > 0 {
	}
}
next_value :: proc(a: int) -> int { return a - 1 }
`,
		config = {enable_code_action_extract_variable = true},
	}
	// select `next_value(a)` in the for condition
	range := common.Range {
		start = {line = 2, character = 5},
		end   = {line = 2, character = 18},
	}
	test.expect_action_not_offered(t, &source, range, "Extract local variable")
}

// The right side of `&&` only evaluates when the left is true — hoisting it
// unconditionally breaks short-circuiting.
@(test)
extract_variable_refuses_short_circuit_rhs :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
run :: proc(p: ^int) {
	ok := p != nil && p^ > 0
	_ = ok
}
`,
		config = {enable_code_action_extract_variable = true},
	}
	// select `p^ > 0`, the rhs of &&
	range := common.Range {
		start = {line = 2, character = 19},
		end   = {line = 2, character = 25},
	}
	test.expect_action_not_offered(t, &source, range, "Extract local variable")
}
