package main

import "core:fmt"
import "core:math/rand"
import "core:mem"
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
	scores = []int{ 30, 20, 10 },
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
	bid: proc(rawptr) -> int,
	auction: proc(rawptr, Auction_Event, bool) -> Auction_Event,
	deinit: proc(rawptr),
}

Player :: struct {
	id: uint,
	cards: [dynamic]Card,
	bought: []uint,
	money: int,
	strat: Strategy,
}

Bid_Event :: struct {
	player: uint,
	amount: int,
}

Pass_Event :: struct {
	player: uint,
}

Win_Event :: struct {
	player: uint,
	card: uint,
	amount: int,
}

Auction_Event :: struct {
	player: uint,
	card: uint,
	double: uint,
	is_double: bool,
	price: int,
}

Resource_Event :: struct {
	cards: []uint,
	money: int,
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
	money: int,
}

Deal_Schedule :: struct {
	players: uint,
	dealt: []Resources,
}

Config :: struct {
	artists: []Artist,
	schedule: []Deal_Schedule,
	scores: []int,
}

state: struct {
	deck: []Card,
	pos: uint,
	round: uint,
	auctioneer: uint,
	artists: []Artist,
	schedule: ^Deal_Schedule,
	reward: []int,
	round_played: []uint,
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

	state.round_played = make([]uint, len(conf.artists))
	state.reward = make([]int, len(conf.artists))

	// shuffle the deck
	rand.shuffle(state.deck)

	// distribute the cards, init the strategies
	state.players = make([]Player, len(strats))
	for &player, i in state.players {
		player.id = uint(i)
		player.cards =
			make([dynamic]Card, 0, state.schedule.dealt[0].cards)
		player.bought = make([]uint, len(conf.artists))
		player.strat = strats[i]
		player.strat.init(&player.strat.ctx, player.id)
	}
	deal_round()
}

packup_game :: proc() {
	delete(state.deck)
	for &p in state.players {
		p.strat.deinit(&p.strat.ctx)
		delete(p.cards)
		delete(p.bought)
	}
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
			money = int(dealing.money),
		})
	}
	state.round += 1
}

update_players :: proc(ev: Event) {
	for player in state.players {
		player.strat.update(player.strat.ctx, ev)
	}
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

is_valid_auction :: proc(auction: Auction_Event) -> string {
	if auction.player >= len(state.players) {
		return fmt.aprintf("player %d is not a valid player",
			auction.player)
	}
	if auction.card >= len(state.deck) {
		return fmt.aprintf("card %d is not a valid card", auction.card)
	}
	if auction.is_double && auction.double >= len(state.deck) {
		return fmt.aprintf("card %d is not a valid card",
			auction.double)
	}

	card := state.deck[auction.card]
	if card.type != .Double && auction.is_double {
		str := card_str(auction.double)
		defer delete(str)
		return fmt.aprintf("cannot hold a double auction with %s", str)
	}

	switch card.type {
	case .Open:
	case .Secret:
	case .Offer:
	case .Fixed:
		if state.players[auction.player].money < auction.price {
			return fmt.aprintf("does not have $%d", auction.price)
		}
	case .Double:
		if !auction.is_double {
			return ""
		}
		double := state.deck[auction.double]
		if double.type == .Double {
			return fmt.aprintf(
				"cannot hold an auction with two double cards")
		}
		if card.artist == double.artist {
			a1 := card_str(auction.card)
			a2 := card_str(auction.double)
			defer delete(a1)
			defer delete(a2)
			return fmt.aprintf("%s and %s are different artists",
				a1, a2)
		}
	}

	return ""
}

run_auction :: proc() {
	max_tries :: 3
	num_players := uint(len(state.players))
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

		if str := is_valid_auction(auction); str != "" {
			defer delete(str)
			fmt.eprintfln("Player %d tried an invalid auction: %s",
				auctioneer_num, str)
			continue
		}

		card_num, ok1 := find_card_num(auctioneer, auction.card)
		if !ok1 {
			str := card_str(auction.card)
			defer delete(str)
			fmt.eprintfln("Player %d tried to auction a card (%s)" +
				" that they don't have", auctioneer.id, str)
			continue
		}

		if !auction.is_double {
			unordered_remove(&state.players[auctioneer_num].cards,
				card_num)
			state.deck[auction.card].public = true
			artist := state.deck[auction.card].artist
			state.round_played[artist] += 1
			if state.round_played[artist] == 5 {
				update_players(auction)
				str := card_str(auction.card)
				defer delete(str)
				fmt.printfln("Round ended with Player %d" +
					" showing %s", auctioneer.id, str)
				return
			}
			success = true
			break
		}

		double_num, ok2 := find_card_num(auctioneer, auction.double)
		if !ok2 {
			str := card_str(auction.double)
			defer delete(str)
			fmt.eprintfln("Player %d tried to auction a card (%s)" +
				" that they don't have", auctioneer.id, str)
			continue
		}

		
		unordered_remove(&state.players[auctioneer_num].cards, card_num)
		state.deck[auction.card].public = true
		card_artist := state.deck[auction.card].artist
		state.round_played[card_artist] += 1
		if state.round_played[card_artist] == 5 {
			update_players(auction)
			str := card_str(auction.card)
			defer delete(str)
			fmt.printfln("Round ended with Player %d showing %s",
				auctioneer.id, str)
			return
		}

		unordered_remove(&state.players[auctioneer_num].cards,
			double_num)
		state.deck[auction.double].public = true
		double_artist := state.deck[auction.double].artist
		state.round_played[double_artist] += 1
		if state.round_played[double_artist] == 5 {
			update_players(auction)
			str_card := card_str(auction.card)
			defer delete(str_card)
			str_double := card_str(auction.double)
			defer delete(str_double)
			fmt.printfln("Round ended with Player %d showing %s" +
				" and %s", auctioneer.id, str_card, str_double)
			return
		}
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
		auctioneer_num = (auctioneer_num + 1) % num_players
		auctioneer = state.players[auctioneer_num]
		if auctioneer_num == state.auctioneer {
			str := card_str(auction.card)
			defer delete(str)
			fmt.printfln("Player %d got %s for free",
				auctioneer.id, str)
			artist := state.deck[auction.card].artist
			state.players[auctioneer_num].bought[artist] += 1
			update_players(Win_Event {
				player = auctioneer_num,
				card = auction.card,
				amount = 0,
			})
			return
		}

		
		second_auction := auctioneer.strat.auction(
			auctioneer.strat.ctx, auction, true)
		card_num, ok := find_card_num(auctioneer, second_auction.double)
		err := is_valid_auction(second_auction)
		defer delete(err)
		if !ok || err != "" || second_auction.card != auction.card ||
				second_auction.player != auctioneer.id {
			continue
		}

		auction = second_auction
		unordered_remove(&state.players[auctioneer_num].cards, card_num)
		state.deck[auction.double].public = true
	}

	str := card_str(auction.card)
	defer delete(str)
	auction_str := fmt.aprintf("Player %d is auctioning %s",
		auctioneer_num, str)
	defer delete(auction_str)
	if auction.is_double {
		str := card_str(auction.double)
		defer delete(str)
		tmp := fmt.aprintf("%s, %s", auction_str, str)
		delete(auction_str)
		auction_str = tmp
	}
	fmt.println(auction_str)
	update_players(auction)

	winner := auctioneer_num
	winning_bid := 0

	type: Auction
	if auction.is_double {
		type = state.deck[auction.double].type
	} else {
		type = state.deck[auction.card].type
	}

	switch type {
	case .Double:
		fmt.eprintln("internal error: attempting to bid on a double" +
			" auction card")
		os.exit(1)
	case .Open:
		outer: for {
			for i in 1..=num_players {
				bidder_num := (winner + uint(i)) % num_players
				bidder := state.players[bidder_num]
				bid := bidder.strat.bid(bidder.strat.ctx)
				if bid > bidder.money {
					fmt.eprintfln("Player %d tried to bid" +
						" $%d but they only have $%d",
						bidder.id, bid, bidder.money)
					bid = 0
				}

				if bid > winning_bid {
					fmt.printfln("Player %d bidding $%d",
						bidder.id, bid)
					winner = bidder_num
					winning_bid = bid
					update_players(Bid_Event {
						player = bidder.id,
						amount = bid,
					})
					continue outer
				}
			}

			for i in 1..<num_players {
				bidder_num := (winner + uint(i)) % num_players
				bidder := state.players[bidder_num]
				bid := bidder.strat.bid(bidder.strat.ctx)
				if bid > bidder.money {
					fmt.eprintfln("Player %d tried to bid" +
						" $%d but they only have $%d",
						bidder.id, bid, bidder.money)
					bid = 0
				}

				if bid > winning_bid {
					fmt.printfln("Player %d bidding $%d",
						bidder.id, bid)
					winner = bidder_num
					winning_bid = bid
					update_players(Bid_Event {
						player = bidder.id,
						amount = bid,
					})
					continue outer
				}
				
			}

			break outer
		}
	case .Offer:
		for i in 1..=num_players {
			bidder_num := (auctioneer_num + uint(i)) % num_players
			bidder := state.players[bidder_num]
			bid := bidder.strat.bid(bidder.strat.ctx)
			if bid > bidder.money {
				fmt.eprintfln("Player %d tried to bid $%d but" +
					" they only have $%d", bidder.id, bid,
					bidder.money)
				bid = 0
			}

			if bid > winning_bid {
				fmt.printfln("Player %d bidding $%d",
					bidder.id, bid)
				winner = bidder.id
				winning_bid = bid
				update_players(Bid_Event {
					player = bidder.id,
					amount = bid,
				})
			} else {
				fmt.printfln("Player %d passing", bidder.id)
				update_players(Pass_Event {
					player = bidder.id,
				})
			}
		}
	case .Fixed:
		winning_bid = auction.price
		for i in 1..<num_players {
			bidder_num := (auctioneer_num + uint(i)) % num_players
			bidder := state.players[bidder_num]
			bid := bidder.strat.bid(bidder.strat.ctx)
			if bid > bidder.money {
				fmt.eprintfln("Player %d tried to bid $%d but" +
					" they only have $%d", bidder.id, bid,
					bidder.money)
				bid = 0
			}

			if bid >= winning_bid {
				update_players(Bid_Event {
					player = bidder.id,
					amount = winning_bid,
				})
			} else {
				update_players(Pass_Event {
					player = bidder.id,
				})
			}

			if bid >= winning_bid {
				fmt.printfln("Player %d bidding $%d",
						bidder.id, bid)
				winner = bidder.id
				break
			} else {
				fmt.printfln("Player %d passing", bidder.id)
			}
		}
	case .Secret:
		bids := make([]int, num_players)
		defer delete(bids)
		for i in 0..<num_players {
			bidder_num := (auctioneer_num + uint(i)) % num_players
			bidder := state.players[bidder_num]
			bid := bidder.strat.bid(bidder.strat.ctx)
			if bid > bidder.money {
				fmt.eprintfln("Player %d tried to bid $%d but" +
					" they only have $%d", bidder.id, bid,
					bidder.money)
				bid = 0
			}
			if bid > winning_bid {
				winning_bid = bid
				winner = bidder.id
			}
			bids[bidder_num] = bid
		}

		for b, i in bids {
			fmt.printfln("Player %d bid $%d", i, b)
		}

		for b, i in bids {
			if b == 0 {
				update_players(Pass_Event {
					 player = uint(i),
				})
			} else {
				update_players(Bid_Event {
					 player = uint(i),
					 amount = b,
				})
			}
		}
	}

	fmt.printfln("Player %d won the bid for $%d", winner, winning_bid)
	update_players(Win_Event {
		player = winner,
		amount = winning_bid,
	})

	artist := state.deck[auction.card].artist
	state.players[winner].bought[artist] += 1
	if auction.is_double {
		state.players[winner].bought[artist] += 1
	}
	state.players[winner].money -= winning_bid
	wp := state.players[winner]
	wp.strat.update(wp.strat.ctx, Resource_Event {
		money = -winning_bid,
	})

	if winner != auctioneer_num {
		state.players[auctioneer_num].money += winning_bid
		auctioneer.strat.update(auctioneer.strat.ctx, Resource_Event {
			money = winning_bid,
		})
	}

}

play_round :: proc() {
	fmt.printfln("=== Round %d ===", state.round)
	mem.zero_slice(state.round_played)
	popularity_overflow :: proc() -> bool {
		for v in state.round_played {
			if v == 5 { return true }
		}
		return false
	}
	for !popularity_overflow() {
		run_auction()
		state.auctioneer = (state.auctioneer + 1) % len(state.players)
	}
	
}

main :: proc() {
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
	strats := []Strategy {
		first_card_all_in,
		first_card_all_in,
		first_card_all_in,
		first_card_all_in,
	}

	setup_game(mart_conf, strats);
	play_round()
	for i in 2..=len(state.schedule.dealt) {
		deal_round()
		play_round()
	}
	fmt.println("Hellope")
}