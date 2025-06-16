package main

import "core:fmt"

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
		random_player,
	}

	setup_game(mart_conf, strats);
	play_round()
	for i in 2..=len(state.schedule.dealt) {
		deal_round()
		play_round()
	}

	fmt.println("")
	for p in state.players {
		fmt.printfln("Player %d ended with $%d", p.id, p.money)
	}
}