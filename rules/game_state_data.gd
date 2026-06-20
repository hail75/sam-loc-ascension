class_name GameStateData
extends RefCounted

## Plain match state — no Node/UI, no behaviour beyond cloning. Everything the
## engine needs to compute the next state lives here, so it can be serialised
## and shipped to/from the future authoritative server unchanged.

var hands: Array = []        # NUM_PLAYERS × Array of [row, col]
var current: int = 0         # whose turn it is (player index)
var table: Array = []        # the current top play, as [row, col] cards
var table_owner: int = -1    # who owns the cards on the table (-1 = fresh lead)
var passed: Array = []       # NUM_PLAYERS bools: who has folded THIS trick and
                             # is locked out until the next trick starts
var finished: bool = false
var winner: int = -1

## Deep copy — the engine never mutates the state it is handed.
func clone() -> GameStateData:
	var s := GameStateData.new()
	for h in hands:
		s.hands.append(h.duplicate(true))
	s.current = current
	s.table = table.duplicate(true)
	s.table_owner = table_owner
	s.passed = passed.duplicate()
	s.finished = finished
	s.winner = winner
	return s
