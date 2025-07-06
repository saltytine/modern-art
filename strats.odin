package main

import "core:fmt"
import "core:math/rand"

strategies :: []struct { name: string, value: Strategy } {
    { name = first_card_all_in, value = first_card_all_in },
    { name = random_player.name, value = random_player },
    { name = expected_return.name, value = expected_return }
}

Strategy_Setup :: struct {
	id: uint,
	conf: Config,
	num_players: uint,
}

Strategy :: struct {
	ctx: rawptr,
	name: string,
	init: proc(^Strategy, Strategy_Setup),
	update: proc(Strategy, Event),
	bid: proc(Strategy) -> int,
	auction: proc(Strategy, Auction_Event, bool) -> Auction_Event,
	deinit: proc(^Strategy),
}

FCAI_Ctx :: struct {
	cards: [dynamic]uint,
	id: uint,
	money: int,
}

first_card_all_in :: Strategy {
	ctx = nil,
	name = "First Card, All In",
	init = proc(self: ^Strategy, setup: Strategy_Setup) {
		c := new(FCAI_Ctx)
		c^ = FCAI_Ctx {
			id = setup.id,
			cards = make([dynamic]uint),
			money = 0,
		}
		self.ctx = c
	},
	update = proc(self: Strategy, event: Event) {
		ctx := cast(^FCAI_Ctx) self.ctx
		#partial switch ev in event {
		case Resource_Event:
			append(&ctx.cards, ..ev.cards)
			ctx.money += ev.money
			delete(ev.cards)
		case Auction_Event:
			for c, i in ctx.cards {
				if c == ev.card {
					unordered_remove(&ctx.cards, i)
					break
				}
			}
			if !ev.is_double { return }
			for c, i in ctx.cards {
				if c == ev.double {
					unordered_remove(&ctx.cards, i)
					break
				}
			}
		}
	},
	bid = proc(self: Strategy) -> int {
		ctx := cast(^FCAI_Ctx) self.ctx
		return ctx.money
	},
	auction = proc(self: Strategy, _: Auction_Event, _: bool) \
			-> Auction_Event {
		ctx := cast(^FCAI_Ctx) self.ctx
		if len(ctx.cards) > 0 {
			return Auction_Event {
				player = ctx.id,
				card = ctx.cards[0],
				double = 0,
				is_double = false,
				price = ctx.money,
			}
		}

		return Auction_Event {}
	},
	deinit = proc(self: ^Strategy) {
		ctx := cast(^FCAI_Ctx) self.ctx
		delete(ctx.cards)
		free(ctx)
		self.ctx = nil
	}
}

Random_Ctx :: struct {
	id: uint,
	cards: [dynamic]uint,
	money: int,
}

random_player :: Strategy {
	ctx = nil,
	name = "Random",
	init = proc(self: ^Strategy, setup: Strategy_Setup) {
		c := new(Random_Ctx)
		c^ = Random_Ctx {
			id = setup.id,
			cards = make([dynamic]uint),
			money = 0,
		}
		self.ctx = c
	},
	update = proc(self: Strategy, event: Event) {
		ctx := cast(^Random_Ctx) self.ctx
		#partial switch ev in event {
		case Resource_Event:
			append(&ctx.cards, ..ev.cards)
			ctx.money += ev.money
			delete(ev.cards)
		case Auction_Event:
			for c, i in ctx.cards {
				if c == ev.card {
					unordered_remove(&ctx.cards, i)
					break
				}
			}
			if !ev.is_double { return }
			for c, i in ctx.cards {
				if c == ev.double {
					unordered_remove(&ctx.cards, i)
					break
				}
			}
		}
	},
	bid = proc(self: Strategy) -> int {
		ctx := cast(^Random_Ctx) self.ctx
		return ctx.money > 0 ? rand.int_max(ctx.money) : 0
	},
	auction = proc(self: Strategy, auction: Auction_Event, \
			second_ask: bool) -> Auction_Event {
		ctx := cast(^Random_Ctx) self.ctx
		price := ctx.money > 0 ? rand.int_max(ctx.money) : 0
		if second_ask {
			card := get_card(auction.card)
			for id in ctx.cards {
				tmp := get_card(id)
				if tmp.type != .Double &&
						tmp.artist == card.artist {
					return Auction_Event {
						player = ctx.id,
						card = auction.card,
						double = tmp.id,
						is_double = true,
						price = price,
					}
				}
			}
			return auction
		}

		card := get_card(rand.choice(ctx.cards[:]))
		if card.type == .Double {
			for id in ctx.cards {
				tmp := get_card(id)
				if id != card.id && tmp.type != .Double &&
						tmp.artist == card.artist {
					return Auction_Event {
						player = ctx.id,
						card = card.id,
						double = tmp.id,
						is_double = true,
						price = price,
					}
				}
			}
		}

		return Auction_Event {
			player = ctx.id,
			card = card.id,
			double = 0,
			is_double = false,
			price = price,
		}
	},
	deinit = proc(self: ^Strategy) {
		ctx := cast(^Random_Ctx) self.ctx
		delete(ctx.cards)
		free(ctx)
		self.ctx = nil
	}
}

ER_Ctx :: struct {
	id: uint,
	base_reward: []int,
	past_reward: []int,
	expected_reward: []int,
	// TODO: Use a priority queue instead of sorting evey round??
	num_auctioned: []uint,
	auction: Auction_Event,
	rnd: Strategy,
}

expected_return :: Strategy {
	ctx = nil,
	name = "Expected Return",
	init = proc(self: ^Strategy, setup: Strategy_Setup) {
		ctx := new(ER_Ctx)
		ctx.id = setup.id
		ctx.base_reward = make([]int, len(setup.conf.scores))
		copy(ctx.base_reward, setup.conf.scores)
		ctx.past_reward = make([]int, len(setup.conf.artists))
		ctx.expected_reward = make([]int, len(setup.conf.artists))
		ctx.num_auctioned = make([]uint, len(setup.conf.artists))
		ctx.rnd = random_player
		ctx.rnd->init(setup)
		self.ctx = ctx
	},
	bid = proc(self: Strategy) -> int {
		ctx := cast(^ER_Ctx) self.ctx
		card := get_card(ctx.auction.card)
		reward := ctx.expected_reward[card.artist]
		if reward > 0 do reward += ctx.past_reward[card.artist]
		return reward * (ctx.auction.is_double ? 2 : 1)
	},
	auction = proc(self: Strategy, auction: Auction_Event, \
			second_ask: bool) -> Auction_Event {
		ctx := cast(^ER_Ctx) self.ctx
		return ctx.rnd->auction(auction, second_ask)
	},
	update = proc(self: Strategy, event: Event) {
		ctx := cast(^ER_Ctx) self.ctx
		#partial switch ev in event {
		case Resource_Event:
			ctx.rnd->update(event)
		case Auction_Event:
			ctx.auction = ev
			card := get_card(ev.card)
			ctx.num_auctioned[card.artist] += ev.is_double ? 2 : 1
			for &v in ctx.expected_reward do v = 0
			num_auctioned := make([]uint, len(ctx.num_auctioned))
			defer delete(num_auctioned)
			copy(num_auctioned, ctx.num_auctioned)
			for reward in ctx.base_reward {
				artist := 0
				max := uint(0)
				for na, idx in num_auctioned {
					if na > max {
						max = na
						artist = idx
					}
				}
				if max == 0 {
					break
				}

				ctx.expected_reward[artist] = reward
				num_auctioned[artist] = 0
			}

			ctx.rnd->update(event)
		case Round_End_Event:
			for i in 0..<len(ctx.past_reward) {
				ctx.past_reward[i] += ctx.expected_reward[i]
				ctx.num_auctioned[i] = 0
				ctx.expected_reward[i] = 0
			}
		}
	},
	deinit = proc(self: ^Strategy) {
		ctx := cast(^ER_Ctx) self.ctx
		ctx.rnd->deinit();
		delete(ctx.past_reward)
		delete(ctx.expected_reward)
		delete(ctx.base_reward)
		delete(ctx.num_auctioned)
		free(ctx)
		self.ctx = nil
	}
}
