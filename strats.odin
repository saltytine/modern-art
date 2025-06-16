package main

import "core:fmt"
import "core:math/rand"

Strategy :: struct {
	ctx: rawptr,
	init: proc(^rawptr, uint),
	update: proc(rawptr, Event),
	bid: proc(rawptr) -> int,
	auction: proc(rawptr, Auction_Event, bool) -> Auction_Event,
	deinit: proc(^rawptr),
}

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
	deinit = proc(ctx: ^rawptr) {
		us := cast(^FCAI_Ctx) ctx
		delete(us.cards)
		free(us)
		ctx^ = nil
	}
}

Random_Ctx :: struct {
	id: uint,
	cards: [dynamic]uint,
	money: int,
}

random_player :: Strategy {
	ctx = nil,
	init = proc(ctx: ^rawptr, us: uint) {
		c := new(Random_Ctx)
		c^ = Random_Ctx {
			id = us,
			cards = make([dynamic]uint),
			money = 0,
		}
		ctx^ = c
	},
	update = proc(ctx: rawptr, event: Event) {
		us := cast(^Random_Ctx) ctx
		#partial switch ev in event {
		case Resource_Event:
			append(&us.cards, ..ev.cards)
			us.money += ev.money
			delete(ev.cards)
		case Auction_Event:
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
		us := cast(^Random_Ctx) ctx
		return rand.int_max(us.money)
	},
	auction = proc(ctx: rawptr, auction: Auction_Event, second_ask: bool) \
			-> Auction_Event {
		us := cast(^Random_Ctx) ctx
		price := rand.int_max(us.money)
		if second_ask {
			card := get_card(auction.card)
			for id in us.cards {
				tmp := get_card(id)
				if tmp.type != .Double &&
						tmp.artist == card.artist {
					return Auction_Event {
						player = us.id,
						card = auction.card,
						double = tmp.id,
						is_double = true,
						price = price,
					}
				}
			}
			return auction
		}

		card := get_card(rand.choice(us.cards[:]))
		if card.type == .Double {
			for id in us.cards {
				tmp := get_card(id)
				if id != card.id && tmp.type != .Double &&
						tmp.artist == card.artist {
					return Auction_Event {
						player = us.id,
						card = card.id,
						double = tmp.id,
						is_double = true,
						price = price,
					}
				}
			}
		}

		return Auction_Event {
			player = us.id,
			card = card.id,
			double = 0,
			is_double = false,
			price = price,
		}
	},
	deinit = proc(ctx: ^rawptr) {
		us := cast(^Random_Ctx) ctx
		delete(us.cards)
		free(us)
		ctx^ = nil
		
	}
}