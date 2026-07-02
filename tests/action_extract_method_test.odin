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

// A selection containing `return` must not be extractable: the return would
// exit the new proc instead of the caller.
@(test)
extract_method_refuses_return_in_selection :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
run :: proc(a: int) {
	if a < 0 {
		return
	}
	use(a)
}
use :: proc(a: int) {}
`,
		config = {enable_code_action_extract_method = true},
	}
	range := common.Range {
		start = {line = 2, character = 1},
		end   = {line = 4, character = 2},
	}
	test.expect_action_not_offered(t, &source, range, "Extract method")
}

// A selection containing `defer` must not be extractable: the defer would
// fire at the end of the new proc instead of the original scope.
@(test)
extract_method_refuses_defer_in_selection :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
run :: proc(a: int) {
	defer use(a)
	use(a)
}
use :: proc(a: int) {}
`,
		config = {enable_code_action_extract_method = true},
	}
	range := common.Range {
		start = {line = 2, character = 1},
		end   = {line = 3, character = 7},
	}
	test.expect_action_not_offered(t, &source, range, "Extract method")
}

// A declaration inside the selection that is used after it would become
// undeclared at the remaining use sites.
@(test)
extract_method_refuses_decl_used_after :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
run :: proc(a: int) {
	c := a + 1
	use(c)
}
use :: proc(a: int) {}
`,
		config = {enable_code_action_extract_method = true},
	}
	range := common.Range {
		start = {line = 2, character = 1},
		end   = {line = 2, character = 11},
	}
	test.expect_action_not_offered(t, &source, range, "Extract method")
}

// A write to a captured (by-value) local would stop updating the caller's
// variable.
@(test)
extract_method_refuses_write_to_captured :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
run :: proc() {
	count := 0
	count += 1
	use(count)
}
use :: proc(a: int) {}
`,
		config = {enable_code_action_extract_method = true},
	}
	range := common.Range {
		start = {line = 3, character = 1},
		end   = {line = 3, character = 11},
	}
	test.expect_action_not_offered(t, &source, range, "Extract method")
}

// A whole loop (with its unlabeled break inside) is fine to extract — the
// branch targets a loop that moves along with it.
@(test)
extract_method_allows_contained_break :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
run :: proc(a: int) {
	for i in 0 ..< a {
		if i > 2 {
			break
		}
	}
	use(a)
}
use :: proc(a: int) {}
`,
		config = {enable_code_action_extract_method = true},
	}
	range := common.Range {
		start = {line = 2, character = 1},
		end   = {line = 6, character = 2},
	}

	check :: proc(t: ^testing.T, edits: []server.TextEdit) {
		testing.expect(t, len(edits) == 2, "expected 2 edits (proc + call)")
	}
	test.expect_action_edits(t, &source, range, "Extract method", check)
}
