package tests

import "core:testing"

import test "src:testing"

// Methodin: methods declared in the *current* document (not just an already
// indexed package) must complete. The open document is now collected into the
// index on refresh, so `x.<method>` offers the struct's own methods.
@(test)
methodin_selector_method_current_file :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Rect :: struct {
			w: int,
			draw :: proc() {},
		}
		main :: proc() {
			r: Rect
			r.{*}
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_completion_labels(t, &source, ".", {"draw"})
}

// Inside an in-struct method body a sibling method is callable bare (the
// compiler rewrites `foo()` to `self.foo()`), so bare-identifier completion
// must offer the enclosing struct's methods.
@(test)
methodin_bare_sibling_method_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Rect :: struct {
			draw :: proc() {},
			redraw :: proc() {
				dr{*}
			},
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_completion_labels(t, &source, "", {"draw"})
}

// `self.` inside an in-struct method body lists the struct's methods (the
// receiver resolves to the named struct, whose methods are name-keyed).
@(test)
methodin_self_selector_method_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Rect :: struct {
			draw :: proc() {},
			redraw :: proc() {
				self.{*}
			},
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_completion_labels(t, &source, ".", {"draw"})
}

// `auto_union(T)` values promote the base type's methods for completion.
@(test)
methodin_auto_union_base_method_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Entity :: struct {
			hp: int,
			hit :: proc() {},
		}
		Enemy :: struct { using e: Entity }
		BaseEntity :: auto_union(Entity)
		main :: proc() {
			b: BaseEntity
			b.{*}
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_completion_labels(t, &source, ".", {"hit"})
}

// Methodin: methods of a `using`-embedded struct must be offered on the derived
// value, transitively (ChaserEnemy -> EnemyBase -> Transform).
@(test)
methodin_embedded_method_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Transform :: struct {
			x: f32,
			get_forward :: proc() -> f32 { return x },
		}
		EnemyBase :: struct {
			using transform: Transform,
			take_damage :: proc(d: int) {},
		}
		ChaserEnemy :: struct { using enemy: EnemyBase, aggro: f32 }
		main :: proc() {
			c: ChaserEnemy
			c.{*}
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_completion_labels(t, &source, ".", {"get_forward", "take_damage"})
}

// Methodin: `auto_union` must be offered as a builtin completion, like auto_cast.
@(test)
methodin_auto_union_keyword_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		asdf :: auto_{*}
		`,
	}
	test.expect_completion_labels(t, &source, "", {"auto_union"})
}

// Union dispatch: `u.` offers exactly the methods present on EVERY variant
// (the compiler only synthesises a dispatcher for those). `bark` is only on
// Dog, so it must not be offered.
@(test)
methodin_union_dispatch_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Animal :: struct {
			greet :: proc() {},
		}
		Dog :: struct {
			greet :: proc() {},
			bark :: proc() {},
		}
		Pet :: union { Animal, Dog }
		main :: proc() {
			p: Pet
			p.{*}
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_completion_labels(t, &source, ".", {"greet"}, {"bark"})
}

// Union dispatch reaches methods a variant inherits through a `using` field.
@(test)
methodin_union_dispatch_completion_using :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Animal :: struct {
			introduce :: proc() {},
		}
		Dog :: struct {
			using base: Animal,
		}
		Cat :: struct {
			using base: Animal,
		}
		Pet :: union { Dog, Cat }
		main :: proc() {
			p: Pet
			p.{*}
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_completion_labels(t, &source, ".", {"introduce"})
}

// Methodin: `Vec3.` with the receiver written as the type's own name offers
// its type-scoped members (in-struct/impl constants) under unmangled names.
@(test)
methodin_type_scoped_constant_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Vec3 :: distinct [3]f32
		impl Vec3 {
			UP :: Vec3{0, 1, 0},
			RIGHT :: Vec3{1, 0, 0},
		}
		main :: proc() {
			v := Vec3.{*}
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_completion_labels(t, &source, ".", {"UP", "RIGHT"})
}

// Struct-body constants complete the same way.
@(test)
methodin_struct_constant_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		World :: struct {
			frame: int,
			MAX_ENTITIES :: 128,
		}
		main :: proc() {
			n := World.{*}
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_completion_labels(t, &source, ".", {"MAX_ENTITIES"})
}

// Rvalue receivers: completion works on temporaries (function results,
// type-scoped constants) — resolution is type-based.
@(test)
methodin_rvalue_receiver_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		World :: struct {
			hp: int,
			describe :: proc() {},
		}
		make_world :: proc() -> World {
			return {}
		}
		main :: proc() {
			make_world().{*}
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_completion_labels(t, &source, ".", {"describe"})
}

// Chained method completion on a type-scoped constant.
@(test)
methodin_constant_chain_completion :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test
		Vec3 :: distinct [3]f32
		impl Vec3 {
			UP :: Vec3{0, 1, 0},
			scaled :: proc(v: Vec3, f: f32) -> Vec3 { return v },
		}
		main :: proc() {
			v := Vec3.UP.{*}
		}
		`,
		config = {enable_fake_method = true},
	}
	test.expect_completion_labels(t, &source, ".", {"scaled"})
}
