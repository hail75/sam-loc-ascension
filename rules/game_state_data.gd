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
var bao_sam: int = -1        # player who declared "báo sâm" this deal (-1 = none).
                             # They lead and must win every trick unblocked.
var bao_sam_failed: bool = false  # set if the declaration was broken (declarer's
                                  # lead got beaten, or they gave up the lead)
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
	s.bao_sam = bao_sam
	s.bao_sam_failed = bao_sam_failed
	s.finished = finished
	s.winner = winner
	return s
