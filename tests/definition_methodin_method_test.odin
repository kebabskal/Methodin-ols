package tests

import "core:testing"

import "src:common"
import test "src:testing"

// Methodin: go-to-definition on a bare sibling method call (`spawn()` ==
// `self.spawn()`) must reach the method's declaration. Mirrors
// odin-daggers/world.odin:224 update_spawn_energy().
@(test)
definition_bare_sibling_method :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
World :: struct {
	frame: int,
	spawn :: proc() {},
	update :: proc() {
		spa{*}wn()
	},
}
`,
		config = {enable_fake_method = true},
	}
	location := common.Location {
		range = {start = {line = 3, character = 1}, end = {line = 3, character = 6}},
	}
	test.expect_definition_locations(t, &source, {location})
}
