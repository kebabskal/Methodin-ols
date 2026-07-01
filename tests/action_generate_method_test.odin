package tests

import "core:strings"
import "core:testing"

import "src:common"
import server "src:server"

import test "src:testing"

// Methodin: calling a non-existent method `w.spawn(1)` should offer
// "Create method spawn on World", inserting a stub with a param per arg.
@(test)
generate_missing_method :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
World :: struct {
	frame: int,
}
run :: proc() {
	w: World
	w.spawn(1)
}
`,
		config = {enable_fake_method = true},
	}
	// cursor on `spawn` at line 6.
	range := common.Range {
		start = {line = 6, character = 5},
		end   = {line = 6, character = 5},
	}

	check :: proc(t: ^testing.T, edits: []server.TextEdit) {
		testing.expect(t, len(edits) == 1, "expected 1 edit (the stub)")
		ok := false
		for e in edits {
			if strings.contains(e.newText, "spawn :: proc(a0: int)") do ok = true
		}
		testing.expect(t, ok, "stub with inferred param missing")
	}

	test.expect_action_edits(t, &source, range, "Create method spawn on World", check)
}
