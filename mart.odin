package main

import "core:fmt"
import "core:math/rand"
import "core:os"

mart_conf :: Config {
	artists = []Artist {
		Artist {
			name = "Manuel Carvalho",
			cards = [Auction]uint {
				.Open = 3,
				.Offer = 3,
				.Secret = 2,
				.Fixed = 2,
				.Double = 2,
			},
		},
		Artist {
			name = "Sigrid Thaler",
			cards = [Auction]uint {
				.Open = 3,
				.Offer = 2,
				.Secret = 3,
				.Fixed = 3,
				.Double = 2,
			},
		},
		Artist {
			name = "Daniel Melim",
			cards = [Auction]uint {
				.Open = 3,
				.Offer = 3,
				.Secret = 3,
				.Fixed = 3,
				.Double = 2,
			},
		},
		Artist {
			name = "Ramon Martins",
			cards = [Auction]uint {
				.Open = 3,
				.Offer = 3,
				.Secret = 3,
				.Fixed = 3,
				.Double = 3,
			},
		},
		Artist {
			name = "Rafael Silveira",
			cards = [Auction]uint {
				.Open = 4,
				.Offer = 3,
				.Secret = 3,
				.Fixed = 3,
				.Double = 3,
			},
		},
	},
	schedule = []Deal_Schedule {
		Deal_Schedule {
			players = 3,
			dealt = []Resources {
				Resources {
					cards = 10,
					money = 100,
				},
				Resources {
					cards = 6,
					money = 0,
				},
				Resources {
					cards = 6,
					money = 0,
				},
				Resources {
					cards = 0,
					money = 0,
				},
			},
		},
		Deal_Schedule {
			players = 4,
			dealt = []Resources {
				Resources {
					cards = 9,
					money = 100,
				},
				Resources {
					cards = 4,
					money = 0,
				},
				Resources {
					cards = 4,
					money = 0,
				},
				Resources {
					cards = 0,
					money = 0,
				},
			},
		},
		Deal_Schedule {
			players = 5,
			dealt = []Resources {
				Resources {
					cards = 8,
					money = 100,
				},
				Resources {
					cards = 3,
					money = 0,
				},
				Resources {
					cards = 3,
					money = 0,
				},
				Resources {
					cards = 0,
					money = 0,
				},
			},
		},
	},
}

Auction :: enum { Open, Offer, Secret, Fixed, Double }
auction_names := [Auction]string {
	.Open = "open",
	.Offer = "single offer",
	.Secret = "secret",
	.Fixed = "fixed price",
	.Double = "double auction",
}

Artist :: struct {
	name: string,
	cards: [Auction]uint,
}

Card :: struct {
	id: uint,
	type: Auction,
	artist: uint,
	public: bool,
}

Strategy :: struct {
	ctx: rawptr,
	init: proc(^rawptr, uint),
	update: proc(rawptr, Event),
	bid: proc(rawptr) -> uint,
	auction: proc(rawptr, Auction_Event, bool) -> Auction_Event,
	deinit: proc(rawptr),
}

Player :: struct {
	id: uint,
	cards: [dynamic]Card,
	bought: [dynamic]Card,
	money: uint,
	strat: Strategy,
}

Bid_Event :: struct {
	player: uint,
	amount: uint,
}

Pass_Event :: struct {
	player: uint,
}

Win_Event :: struct {
	player: uint,
	card: uint,
	amount: uint,
}

Auction_Event :: struct {
	player: uint,
	card: uint,
	double: uint,
	is_double: bool,
	price: uint,
}

Resource_Event :: struct {
	cards: []uint,
	money: uint,
}

Event :: union {
	Bid_Event,
	Pass_Event,
	Win_Event,
	Auction_Event,
	Resource_Event,
}

Resources :: struct {
	cards: uint,
	money: uint,
}

Deal_Schedule :: struct {
	players: uint,
	dealt: []Resources,
}

Config :: struct {
	artists: []Artist,
	schedule: []Deal_Schedule,
}

state: struct {
	deck: []Card,
	pos: uint,
	round: uint,
	auctioneer: uint,
	artists: []Artist,
	schedule: ^Deal_Schedule,
	players: []Player,
	events: [dynamic]Event,
}

setup_game :: proc(conf: Config, strats: []Strategy) {
	state.artists = conf.artists

	// create the deck
	num_cards: uint = 0
	for artist in conf.artists {
		for num in artist.cards {
			num_cards += num
		}
	}

	cards_rounds: uint = 0
	for sched in conf.schedule {
		if sched.players == len(strats) {
			state.schedule = new(Deal_Schedule)
			state.schedule^ = sched
			for res in sched.dealt {
				cards_rounds += res.cards
			}
			break
		}
	}

	if state.schedule == nil {
		fmt.eprintfln("config doesn't have a game for %d players",
	     		len(strats))
	     	os.exit(1)
	}

	if len(state.schedule.dealt) == 0 {
		fmt.println("empty deal schedule. Nothing to do.")
		os.exit(0)
	}

	if cards_rounds >= num_cards {
		fmt.eprintfln("bad config. Deal schedule expected %d cards," +
			" but artists only have %d cards total.",
			cards_rounds, num_cards)
		os.exit(1)
	}

	state.deck = make([]Card, num_cards)
	pos: uint
	for artist, idx in conf.artists {
		for num, type in artist.cards {
			for i in 0..<num {
				state.deck[pos] = Card {
					id = pos,
					type = type,
					artist = uint(idx),
				}
				pos += 1
			}
		}
	}

	// shuffle the deck
	rand.shuffle(state.deck)

	// distribute the cards, init the strategies
	state.players = make([]Player, len(strats))
	for &player, i in state.players {
		player.id = uint(i)
		player.cards =
			make([dynamic]Card, 0, state.schedule.dealt[0].cards)
		player.bought = make([dynamic]Card)
		player.strat = strats[i]
		player.strat.init(&player.strat.ctx, player.id)
	}
	deal_round()
}

packup_game :: proc() {
	delete(state.deck)
	delete(state.players)
	free(state.schedule)
	delete(state.events)
}

deal_round :: proc() {
	if state.round >= len(state.schedule.dealt) {
		fmt.eprintfln("attempted to play round %d when schedule only" +
			" supports %d rounds",
			state.round + 1, len(state.schedule.dealt))
		os.exit(1)
	}

	dealing := state.schedule.dealt[state.round]
	for &player in state.players {
		card_ids := make([]uint, dealing.cards)
		for j in 0..<dealing.cards {
			append(&player.cards, state.deck[state.pos])
			card_ids[j] = state.deck[state.pos].id
			state.pos += 1
		}
		player.money += dealing.money
		player.strat.update(player.strat.ctx, Resource_Event {
			cards = card_ids,
			money = dealing.money,
		})
	}
	state.round += 1
}

update_players :: proc(ev: Event) {
	for player in state.players {
		player.strat.update(player.strat.ctx, ev)
	}
}

next_auctioneer :: proc() {
	state.auctioneer = (state.auctioneer + 1) % len(state.players)
}

find_card_num :: proc(player: Player, card: uint) -> (uint, bool) {
	for c, i in player.cards {
		if c.id == card {
			return uint(i), true
		}
	}

	return uint(0), false
}

card_str :: proc(card_id: uint) -> string {
	if card_id >= len(state.deck) {
		return fmt.aprintf("<<invalid id %d>>", card_id)
	}
	card := state.deck[card_id]
	return fmt.aprintf("%d %s (%s)", card_id,
		state.artists[card.artist].name, auction_names[card.type])
}

run_auction :: proc(auction: Auction) {
}

play_round :: proc() {
	fmt.printfln("=== Round %d ===", state.round)

	max_tries :: 3
	auctioneer_num := state.auctioneer
	auctioneer := state.players[auctioneer_num]
	auction: Auction_Event
	
	success := false
	for num_tries in 1..=max_tries {
		auction = auctioneer.strat.auction(
			auctioneer.strat.ctx, Auction_Event{}, false)
		if auction.player != auctioneer.id {
			fmt.eprintfln("Player %d attempted to auction on" +
				" behalf of player %d",
				auctioneer.id, auction.player)
			continue
		}

		card_num, ok1 := find_card_num(auctioneer, auction.card)
		if !ok1 {
			str := card_str(auction.card)
			fmt.eprintfln("Player %d tried to auction a card (%s)" +
				" that they don't have", auctioneer.id, str)
			delete(str)
			continue
		}

		if !auction.is_double {
			unordered_remove(&state.players[auctioneer_num].cards,
				card_num)
			state.deck[card_num].public = true
			success = true
			break
		}

		double_num, ok2 := find_card_num(auctioneer, auction.double)
		if !ok2 {
			str := card_str(auction.double)
			fmt.eprintfln("Player %d tried to auction a card (%s)" +
				" that they don't have", auctioneer.id, str)
			delete(str)
			continue
		}

		
		unordered_remove(&state.players[auctioneer_num].cards, card_num)
		unordered_remove(&state.players[auctioneer_num].cards,
			double_num)
		state.deck[auction.card].public = true
		state.deck[auction.double].public = true
		success = true
		break
	}

	if !success {
		fmt.eprintfln("Player %d could not play a valid card",
			auctioneer.id)
		os.exit(1)
	}

	update_players(auction)
	for state.deck[auction.card].type == .Double && !auction.is_double {
		auctioneer_num = (auctioneer_num + 1) % len(state.players)
		auctioneer = state.players[auctioneer_num]
		if auctioneer_num == state.auctioneer {
			str := card_str(auction.card)
			fmt.printfln("Player %d got %s for free",
				auctioneer.id, str)
			delete(str)
			append(&state.players[auctioneer_num].bought,
				state.deck[auction.card])
			update_players(Win_Event {
				player = auctioneer_num,
				card = auction.card,
				amount = 0,
			})
			next_auctioneer()
			return
		}

		
		second_auction := auctioneer.strat.auction(
			auctioneer.strat.ctx, auction, true)
		card_num, ok := find_card_num(auctioneer, second_auction.double)
		if !ok || state.deck[second_auction.double].type == .Double ||
				second_auction.card != auction.card ||
				second_auction.player != auctioneer.id {
			continue
		}

		auction = second_auction
		unordered_remove(&state.players[auctioneer_num].cards, card_num)
		state.deck[auction.double].public = true
	}

	str := card_str(auction.card)
	auction_str := fmt.aprintf("Auctioning %s", str)
	delete(str)
	if auction.is_double {
		str := card_str(auction.double)
		tmp := fmt.aprintf("%s, %s", auction_str, str)
		delete(str)
		delete(auction_str)
		auction_str = tmp
	}
	fmt.println(auction_str)
	delete(auction_str)

	update_players(auction)
	if auction.is_double {
		run_auction(state.deck[auction.double].type)
	} else {
		run_auction(state.deck[auction.card].type)
	}
	next_auctioneer()
}

main :: proc() {
	Null_Ctx :: struct {
		cards: [dynamic]uint,
		id: uint,
		money: uint,
	}
	null_strat :: Strategy {
		ctx = nil,
		init = proc(ctx: ^rawptr, us: uint) {
			c := new(Null_Ctx)
			c^ = Null_Ctx {
				id = us,
				cards = make([dynamic]uint),
				money = 0,
			}
			ctx^ = c
		},
		update = proc(ctx: rawptr, event: Event) {
			us := cast(^Null_Ctx) ctx
			switch ev in event {
			case Resource_Event:
				append(&us.cards, ..ev.cards)
				us.money += ev.money
				delete(ev.cards)
			case Bid_Event:
			case Pass_Event:
			case Win_Event:
			case Auction_Event:
			}
		},
		bid = proc(ctx: rawptr) -> uint {
			us := cast(^Null_Ctx) ctx
			return us.money
		},
		auction = proc(ctx: rawptr, _: Auction_Event, _: bool) \
				-> Auction_Event {
			us := cast(^Null_Ctx) ctx
			return Auction_Event {
				player = us.id,
				card = us.cards[0],
				double = 0,
				is_double = false,
				price = 1,
			}
		},
		deinit = proc(ctx: rawptr) {
			us := cast(^Null_Ctx) ctx
			delete(us.cards)
			free(us)
		}
	}
	strats := []Strategy {
		null_strat,
		null_strat,
		null_strat,
		null_strat,
	}

	setup_game(mart_conf, strats);
	play_round()
	for i in 2..=len(state.schedule.dealt) {
		deal_round()
		play_round()
	}
	fmt.println("Hellope")
}
