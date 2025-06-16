package main

Config :: struct {
	artists: []Artist,
	schedule: []Deal_Schedule,
	scores: []int,
}

Deal_Schedule :: struct {
	players: uint,
	dealt: []Resources,
}

Resources :: struct {
	cards: uint,
	money: int,
}

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