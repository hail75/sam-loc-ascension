class_name Deck
extends RefCounted

## Pure deck helper — no Node/UI. A card is a [row, col] pair indexing the
## Cards.png sheet: rows 0-3 are the four suits, cols 0-12 are A,2,3…K.
## (This is the kind of pure logic that ports straight to the Python server.)

const SUITS := 4
const RANKS := 13

## A full 52-card deck, Fisher-Yates shuffled with the supplied RNG so the
## result is deterministic for a given seed.
static func make_shuffled(rng: RandomNumberGenerator) -> Array:
	var d: Array = []
	for r in SUITS:
		for c in RANKS:
			d.append([r, c])
	for i in range(d.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Array = d[i]
		d[i] = d[j]
		d[j] = tmp
	return d
