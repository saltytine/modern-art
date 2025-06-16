package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:os"
import "core:sort"

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
	amount: int,
	auction: Auction_Event,
}

Round_End_Event :: struct {}

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
	Round_End_Event,
	Auction_Event,
	Resource_Event,
}

state: struct {
	deck: []Card,
	pos: uint,
	round: uint,
	auctioneer: uint,
	artists: []Artist,
	schedule: ^Deal_Schedule,
	reward_base: []int,
	reward: []int,
	round_played: []uint,
	players: []Player,
	events: [dynamic]Event,
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

// TODO: make this robust against querying cards that aren't ours
get_card :: proc(card_id: uint) -> Card {
	for c in state.deck {
		if c.id == card_id {
			return c
		}
	}

	return Card{}
}

main :: proc() {
	strats := []Strategy {
		random_player,
		random_player,
		random_player,
		expected_return,
	}

	mode := os.S_IRUSR | os.S_IWUSR | os.S_IRGRP | os.S_IROTH
	flags := os.O_CREATE | os.O_TRUNC | os.O_RDWR
	fd, err := os.open("log.txt", flags, mode)
	// TODO: Wtf happened here before
	logger: runtime.Logger
	if err == os.ERROR_NONE {
		opts := bit_set[runtime.Logger_Option] { .Level }
		logger = log.create_file_logger(fd, opt = opts)
	} else {
		logger = log.nil_logger()
	}
	context.logger = logger
	defer if err == os.ERROR_NONE {
		log.destroy_file_logger(logger)
		os.close(fd)
	}

	// TODO: remove this and do actual stats
	wins := make([]uint, len(strats))
	for i in 1..=1000 {
		setup_game(mart_conf, strats);
		play_game()
		sort.merge_sort_proc(state.players, proc(p, q: Player) -> int {
			return q.money - p.money
		})

		winner := state.players[0]
		wins[winner.id] += 1
		fmt.printfln("%d,%d,%d", winner.id, winner.money,
			winner.money - state.players[1].money)
		packup_game()
	}

	for w, i in wins {
		log.infof("Player %d won %d times", i, w)
	}
}