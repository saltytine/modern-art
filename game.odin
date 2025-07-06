package main

import "core:fmt"
import "core:log"
import "core:math/rand"
import "core:mem"
import "core:os"

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
		str := card_str(auction.card)
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
		if card.artist != double.artist {
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

update_players :: proc(ev: Event) {
	for player in state.players {
		player.strat->update(ev)
	}
}

setup_game :: proc(conf: Config, strats: []Strategy) {
	state.pos = 0
	state.round = 0
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
		log.errorf("config doesn't have a game for %d players",
	     		len(strats))
	     	os.exit(1)
	}

	if len(state.schedule.dealt) == 0 {
		fmt.println("empty deal schedule. Nothing to do.")
		os.exit(0)
	}

	if cards_rounds >= num_cards {
		log.errorf("bad config. Deal schedule expected %d cards," +
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
					type = type,
					artist = uint(idx),
				}
				pos += 1
			}
		}
	}

	state.round_played = make([]uint, len(conf.artists))
	state.reward = make([]int, len(conf.artists))
	state.reward_base = conf.scores

	// shuffle the deck
	rand.shuffle(state.deck)
	for &c, i in state.deck {
		c.id = uint(i)
	}

	// distribute the cards, init the strategies
	state.players = make([]Player, len(strats))
	for &player, i in state.players {
		player.id = uint(i)
		player.cards =
			make([dynamic]Card, 0, state.schedule.dealt[0].cards)
		player.bought = make([]uint, len(conf.artists))
		player.strat = strats[i]
		player.strat->init(Strategy_Setup {
			id = player.id,
			conf = conf,
			num_players = len(state.players),
		})
	}
	deal_round()
}

packup_game :: proc() {
	for &p in state.players {
		p.strat->deinit()
		delete(p.cards)
		delete(p.bought)
	}
	delete(state.players)
	delete(state.deck)
	free(state.schedule)
	delete(state.events)
	delete(state.reward)
}

deal_round :: proc() {
	if state.round >= len(state.schedule.dealt) {
		log.errorf("attempted to play round %d when schedule only" +
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
		player.strat->update(Resource_Event {
			cards = card_ids,
			money = int(dealing.money),
		})
	}
	state.round += 1
}

run_auction :: proc() {
	max_tries :: 3
	num_players := uint(len(state.players))
	auctioneer_num := state.auctioneer
	auctioneer := state.players[auctioneer_num]
	auction: Auction_Event

	success := false
	for num_tries in 1..=max_tries {
		auction = auctioneer.strat->auction(Auction_Event{}, false)
		if auction.player != auctioneer.id {
			log.errorf("Player %d attempted to auction on" +
				" behalf of player %d",
				auctioneer.id, auction.player)
			continue
		}

		if str := is_valid_auction(auction); str != "" {
			defer delete(str)
			log.errorf("Player %d tried an invalid auction: %s",
				auctioneer_num, str)
			continue
		}

		card_num, ok1 := find_card_num(auctioneer, auction.card)
		if !ok1 {
			str := card_str(auction.card)
			defer delete(str)
			log.errorf("Player %d tried to auction a card (%s)" +
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
				log.infof("Round ended with Player %d" +
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
			log.errorf("Player %d tried to auction a card (%s)" +
				" that they don't have", auctioneer.id, str)
			continue
		}


		unordered_remove(&state.players[auctioneer_num].cards, card_num)
		state.deck[auction.card].public = true
		card_artist := state.deck[auction.card].artist
		state.round_played[card_artist] += 1
		if state.round_played[card_artist] == 5 {
			auction.double = 0
			auction.is_double = false
			update_players(auction)
			str := card_str(auction.card)
			defer delete(str)
			log.infof("Round ended with Player %d showing %s",
				auctioneer.id, str)
			return
		}

		double_num, ok2 = find_card_num(auctioneer, auction.double)
		if !ok2 {
			str := card_str(auction.double)
			log.errorf("internal error: player %d magically" +
				" lost a card (%s)", auctioneer_num,
				str)
			os.exit(1)
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
			log.infof("Round ended with Player %d showing %s" +
				" and %s", auctioneer.id, str_card, str_double)
			return
		}
		success = true
		break
	}

	if !success {
		log.errorf("Player %d could not play a valid card",
			auctioneer.id)
		os.exit(1)
	}

	for state.deck[auction.card].type == .Double && !auction.is_double {
		auctioneer_num = (auctioneer_num + 1) % num_players
		auctioneer = state.players[auctioneer_num]
		if auctioneer_num == state.auctioneer {
			str := card_str(auction.card)
			defer delete(str)
			log.infof("Player %d got %s for free",
				auctioneer.id, str)
			artist := state.deck[auction.card].artist
			state.players[auctioneer_num].bought[artist] += 1
			update_players(auction)
			update_players(Win_Event {
				player = auctioneer_num,
				auction = auction,
				amount = 0,
			})
			return
		}


		second_auction := auctioneer.strat->auction(auction, true)
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
		state.auctioneer = auctioneer_num
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
	log.info(auction_str)
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
			for i in 1..<num_players {
				bidder_num := (winner + uint(i)) % num_players
				bidder := state.players[bidder_num]
				bid := bidder.strat->bid()
				if bid > bidder.money {
					log.errorf("Player %d tried to bid" +
						" $%d but they only have $%d",
						bidder.id, bid, bidder.money)
					bid = 0
				}

				if bid > winning_bid {
					log.infof("Player %d bidding $%d",
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
				bid := bidder.strat->bid()
				if bid > bidder.money {
					log.errorf("Player %d tried to bid" +
						" $%d but they only have $%d",
						bidder.id, bid, bidder.money)
					bid = 0
				}

				if bid > winning_bid {
					log.infof("Player %d bidding $%d",
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
			bid := bidder.strat->bid()
			if bid > bidder.money {
				log.errorf("Player %d tried to bid $%d but" +
					" they only have $%d", bidder.id, bid,
					bidder.money)
				bid = 0
			}

			if bid > winning_bid {
				log.infof("Player %d bidding $%d",
					bidder.id, bid)
				winner = bidder.id
				winning_bid = bid
				update_players(Bid_Event {
					player = bidder.id,
					amount = bid,
				})
			} else {
				log.infof("Player %d passing", bidder.id)
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
			bid := bidder.strat->bid()
			if bid > bidder.money {
				log.errorf("Player %d tried to bid $%d but" +
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
				log.infof("Player %d bidding $%d",
						bidder.id, auction.price)
				winner = bidder.id
				break
			} else {
				log.infof("Player %d passing", bidder.id)
			}
		}
	case .Secret:
		bids := make([]int, num_players)
		defer delete(bids)
		for i in 0..<num_players {
			bidder_num := (auctioneer_num + uint(i)) % num_players
			bidder := state.players[bidder_num]
			bid := bidder.strat->bid()
			if bid > bidder.money {
				log.errorf("Player %d tried to bid $%d but" +
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
			log.infof("Player %d bid $%d", i, b)
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

	log.infof("Player %d won the bid for $%d", winner, winning_bid)
	update_players(Win_Event {
		player = winner,
		amount = winning_bid,
		auction = auction,
	})

	artist := state.deck[auction.card].artist
	state.players[winner].bought[artist] += 1
	if auction.is_double {
		state.players[winner].bought[artist] += 1
	}
	state.players[winner].money -= winning_bid
	wp := state.players[winner]
	wp.strat->update(Resource_Event { money = -winning_bid })

	if winner != auctioneer_num {
		state.players[auctioneer_num].money += winning_bid
		auctioneer.strat->update(Resource_Event { money = winning_bid })
	}

}

play_round :: proc() {
	log.infof("=== Round %d ===", state.round)
	mem.zero_slice(state.round_played)
	for &p in state.players {
		mem.zero_slice(p.bought)
	}

	popularity_overflow :: proc() -> bool {
		for v in state.round_played {
			if v == 5 { return true }
		}
		return false
	}

	round_check := false
	for i := 0; i < len(state.players) && !popularity_overflow(); i += 1 {
		if state.round == len(state.schedule.dealt) && !round_check {
			round_check = true
			num_cards := 0
			for p in state.players {
				num_cards += len(p.cards)
			}

			if num_cards == 1 {
				for p in state.players {
					if len(p.cards) == 0 {
						continue
					}
					artist := p.cards[0].artist
					state.round_played[artist] += 1
					break
				}
				break
			}
		} if len(state.players[state.auctioneer].cards) > 0 {
			i = 0
			round_check = false
			run_auction()
		}
		state.auctioneer = (state.auctioneer + 1) % len(state.players)
	}

	curr := 0
	last := len(state.reward_base)
	if last > len(state.round_played) {
		last = len(state.round_played)
	}

	for curr < last {
		idx := 0
		max := uint(0)
		for rp, i in state.round_played {
			if rp > max {
				max = rp
				idx = i
			}
		}

		if max == 0 {
			break
		}
		log.infof("%d place - %s", curr + 1, state.artists[idx].name)

		state.reward[idx] += state.reward_base[curr]
		for &p in state.players {
			prize := int(p.bought[idx]) * state.reward[idx]
			p.money += prize
			log.infof("Player %d received $%d for their %d %ss",
				p.id, prize, p.bought[idx],
				state.artists[idx].name)
			p.strat->update(Resource_Event { money = prize })
		}

		state.round_played[idx] = 0
		curr += 1
	}

	update_players(Round_End_Event {})
}

play_game :: proc() {
	play_round()
	for i in 2..=len(state.schedule.dealt) {
		deal_round()
		play_round()
	}

	for p in state.players {
		log.infof("Player %d ended with $%d", p.id, p.money)
	}
}
