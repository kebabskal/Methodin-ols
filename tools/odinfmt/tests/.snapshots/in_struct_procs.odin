package odinfmt_test

// In-struct proc decls and impl blocks should round-trip through
// odinfmt without losing the method declarations.

Player :: struct {
	hp: int,
	damage :: proc(amount: int) {
		hp -= amount
	},
	heal :: proc(amount: int) {
		hp += amount
	},
	mp: int,
}

impl Player {
	reset :: proc() {
		hp = 100
		mp = 50
	}
}
