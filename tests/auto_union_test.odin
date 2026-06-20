package tests

import "core:testing"

import test "src:testing"

// Methodin: `auto_union(T)` must resolve to a union of every struct that
// `using`-embeds T (transitively), and hovering the alias should reveal which
// structs are included.
@(test)
auto_union_hover_lists_variants :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Entity :: struct { hp: int }
		Player :: struct { using entity: Entity, score: int }
		Enemy  :: struct { using enemy_base: Entity, damage: int }
		ExploderEnemy :: struct { using enemy: Enemy, radius: f32 }
		Widget :: struct { label: string }

		Base{*}Entity :: auto_union(Entity)
		`,
	}
	test.expect_hover(t, &source, "test.BaseEntity :: union {\n\tEnemy,\n\tExploderEnemy,\n\tPlayer,\n}")
}

// A variable of the auto_union type should report the alias name, not the
// literal builtin name "auto_union".
@(test)
auto_union_variable_reports_alias_name :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Entity :: struct { hp: int }
		Player :: struct { using entity: Entity, score: int }
		BaseEntity :: auto_union(Entity)
		main :: proc() {
			e{*}: BaseEntity
		}
		`,
	}
	test.expect_hover(t, &source, "test.e: test.BaseEntity")
}
