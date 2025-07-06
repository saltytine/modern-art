package main

import "base:runtime"
import "core:flags"
import "core:fmt"
import "core:log"
import "core:os"
import "core:sort"

Options :: struct {
	// TODO: make this a string and parse it manually (current defaults to
	// stdout
	log_file: os.Handle `args:"file=rwct,perms=644"`,
	log_file_set: bool,
	strats: [dynamic]Strategy `args:"name=strategy,required=4<5"`,
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

opt_parser :: proc (
	data: rawptr,
	data_type: typeid,
	stream: string,
	tag: string,
) -> (
	error: string,
	handled: bool,
	alloc_error: runtime.Allocator_Error
) {
	if data_type == Strategy {
		handled = true
		ptr := cast(^Strategy) data
		for s in strategies {
			if stream == s.name {
				ptr^ = s.value
				return
			}
		}

		// TODO: list strats in msg
		error = "Unknown strategy. Must be one of TODO: list strats"
	}

	return
}

opt_validator :: proc (
	model: rawptr,
	name: string,
	value: any,
	arg_tags: string,
) -> (error: string) {
	return
}

main :: proc() {
	opts: Options
	flags.register_type_setter(opt_parser)
	flags.register_flag_checker(opt_validator)
	flags.parse_or_exit(&opts, os.args, .Odin)

	logger: runtime.Logger
	if true {
		log_opts := bit_set[runtime.Logger_Option] { .Level }
		logger = log.create_file_logger(opts.log_file, opt = log_opts)
	} else {
		logger = log.nil_logger()
	}
	context.logger = logger
	defer if true {
		log.destroy_file_logger(logger)
		os.close(opts.log_file)
	}

	// TODO: remove this and do actual stats
	wins := make([]uint, len(opts.strats))
	for i in 1..=1000 {
		setup_game(mart_conf, opts.strats[:]);
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
