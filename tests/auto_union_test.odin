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

// `e.` on an auto_union value should offer the promoted base members.
@(test)
auto_union_completion_promotes_base_members :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Entity :: struct {
			hp:    int,
			alive: bool,
			take_damage :: proc(amount: int) { hp -= amount },
		}
		Player :: struct { using entity: Entity, score: int }
		BaseEntity :: auto_union(Entity)
		main :: proc() {
			e: BaseEntity
			e.{*}
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_completion_labels(t, &source, ".", {"hp", "alive"})
}

// `e.hp` on an auto_union value should resolve to the promoted base field.
@(test)
auto_union_resolves_promoted_field :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Entity :: struct { hp: int }
		Player :: struct { using entity: Entity, score: int }
		BaseEntity :: auto_union(Entity)
		main :: proc() {
			e: BaseEntity
			e.h{*}p = 1
		}
		`,
	}
	test.expect_hover(t, &source, "Entity.hp: int")
}

// Regression: two auto_union aliases in one file must not send resolution into
// the self-re-entrant, DeferredDepth-deep, full-workspace scan that previously
// blew up time and RAM (exponential in the number of unions). This test simply
// completing quickly IS the guard; the hover also confirms correctness is intact.
@(test)
auto_union_multiple_unions_no_blowup :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Entity :: struct { hp: int }
		Thing  :: struct { size: int }
		Player :: struct { using entity: Entity, score: int }
		Enemy  :: struct { using entity: Entity, damage: int }

		Actors  :: auto_union(Entity)
		Th{*}ings :: auto_union(Thing)
		World :: struct { actors: [dynamic]Actors, things: [dynamic]Things }
		`,
	}
	test.expect_hover(t, &source, "test.Things :: union{}")
}
