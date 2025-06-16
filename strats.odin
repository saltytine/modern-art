package main

FCAI_Ctx :: struct {
	cards: [dynamic]uint,
	id: uint,
	money: int,
}

first_card_all_in :: Strategy {
	ctx = nil,
	init = proc(ctx: ^rawptr, us: uint) {
		c := new(FCAI_Ctx)
		c^ = FCAI_Ctx {
			id = us,
			cards = make([dynamic]uint),
			money = 0,
		}
		ctx^ = c
	},
	update = proc(ctx: rawptr, event: Event) {
		us := cast(^FCAI_Ctx) ctx
		#partial switch ev in event {
		case Resource_Event:
			append(&us.cards, ..ev.cards)
			us.money += ev.money
			delete(ev.cards)
		case Auction_Event:
			if ev.player != us.id { return }
			for c, i in us.cards {
				if c == ev.card {
					unordered_remove(&us.cards, i)
					break
				}
			}
			if !ev.is_double { return }
			for c, i in us.cards {
				if c == ev.double {
					unordered_remove(&us.cards, i)
					break
				}
			}
		}
	},
	bid = proc(ctx: rawptr) -> int {
		us := cast(^FCAI_Ctx) ctx
		return us.money
	},
	auction = proc(ctx: rawptr, _: Auction_Event, _: bool) \
			-> Auction_Event {
		us := cast(^FCAI_Ctx) ctx
		return Auction_Event {
			player = us.id,
			card = us.cards[0],
			double = 0,
			is_double = false,
			price = us.money,
		}
	},
	deinit = proc(ctx: rawptr) {
		us := cast(^FCAI_Ctx) ctx
		delete(us.cards)
		free(us)
	}
}