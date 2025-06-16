package main

import "core:fmt"
import "core:math/rand"

Strategy_Setup :: struct {
	id: uint,
	conf: Config,
	num_players: uint,
}

Strategy :: struct {
	ctx: rawptr,
	name: string,
	init: proc(^rawptr, Strategy_Setup),
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
	name = "First Card, All In",
	init = proc(ctx: ^rawptr, setup: Strategy_Setup) {
		c := new(FCAI_Ctx)
		c^ = FCAI_Ctx {
			id = setup.id,
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
		if len(us.cards) > 0 {
			return Auction_Event {
				player = us.id,
				card = us.cards[0],
				double = 0,
				is_double = false,
				price = us.money,
			}
		}

		return Auction_Event {}
	},
	deinit = proc(ctx: ^rawptr) {
		us := cast(^FCAI_Ctx) ctx^
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
	name = "Random",
	init = proc(ctx: ^rawptr, setup: Strategy_Setup) {
		c := new(Random_Ctx)
		c^ = Random_Ctx {
			id = setup.id,
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
		return us.money > 0 ? rand.int_max(us.money) : 0
	},
	auction = proc(ctx: rawptr, auction: Auction_Event, second_ask: bool) \
			-> Auction_Event {
		us := cast(^Random_Ctx) ctx
		price := us.money > 0 ? rand.int_max(us.money) : 0
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
		us := cast(^Random_Ctx) ctx^
		delete(us.cards)
		free(us)
		ctx^ = nil
	}
}

ER_Ctx :: struct {
	id: uint,
	money: int,
	cards: [dynamic]uint,
	base_reward: []int,
	past_reward: []int,
	expected_reward: []int,
	// TODO: Use a priority queue instead of sorting evey round??
	num_auctioned: []uint,
	auction: Auction_Event,
}

expected_return :: Strategy {
	ctx = nil,
	name = "Expected Return",
	init = proc(ctx: ^rawptr, setup: Strategy_Setup) {
		us := new(ER_Ctx)
		us.id = setup.id
		us.cards = make([dynamic]uint)
		us.base_reward = make([]int, len(setup.conf.scores))
		copy(us.base_reward, setup.conf.scores)
		us.past_reward = make([]int, len(setup.conf.artists))
		us.expected_reward = make([]int, len(setup.conf.artists))
		us.num_auctioned = make([]uint, len(setup.conf.artists))
		ctx^ = us
	},
	bid = proc(ctx: rawptr) -> int {
		us := cast(^ER_Ctx) ctx
		card := get_card(us.auction.card)
		reward := us.expected_reward[card.artist]
		if reward > 0 do reward += us.past_reward[card.artist]
		return reward * (us.auction.is_double ? 2 : 1)
	},
	auction = proc(ctx: rawptr, auction: Auction_Event, second_ask: bool) \
			-> Auction_Event {
		us := cast(^ER_Ctx) ctx
		price := us.money > 0 ? rand.int_max(us.money) : 0
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
	update = proc(ctx: rawptr, event: Event) {
		us := cast(^ER_Ctx) ctx
		#partial switch ev in event {
		case Resource_Event:
			append(&us.cards, ..ev.cards)
			us.money += ev.money
			delete(ev.cards)
		case Auction_Event:
			us.auction = ev
			card := get_card(ev.card)
			us.num_auctioned[card.artist] += ev.is_double ? 2 : 1
			for &v in us.expected_reward do v = 0
			num_auctioned := make([]uint, len(us.num_auctioned))
			defer delete(num_auctioned)
			copy(num_auctioned, us.num_auctioned)
			for reward in us.base_reward {
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

				us.expected_reward[artist] = reward
				num_auctioned[artist] = 0
			}

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
		case Round_End_Event:
			for i in 0..<len(us.past_reward) {
				us.past_reward[i] += us.expected_reward[i]
				us.num_auctioned[i] = 0
				us.expected_reward[i] = 0
			}
		}
	},
	deinit = proc(ctx: ^rawptr) {
		us := cast(^ER_Ctx) ctx^
		delete(us.cards)
		delete(us.past_reward)
		delete(us.expected_reward)
		delete(us.base_reward)
		delete(us.num_auctioned)
		free(us)
		ctx^ = nil
	}
}