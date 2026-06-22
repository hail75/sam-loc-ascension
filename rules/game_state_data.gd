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
var chop_level: int = 0      # depth of the current trick's chop (chặt) chain: 0 =
                             # no chop yet, 1 = first chop, 2 = a chop of that chop,
                             # … — each level multiplies the chặt payment
var an_trang_winner: int = -1  # player who instant-won on the deal (ĂN TRẮNG); set
                             # before any play. -1 = no instant win this deal.
var den_feeder: int = -1     # set on the winning play: the player whose single the
                             # 1-card winner just beat to go out, IF that single wasn't
                             # their highest (they still held a higher one). They pay the
                             # đền penalty in settle. -1 = nobody owes it.
var den_eligible: bool = false  # true iff the table card was placed by a SINGLE play with
                             # no pass since — so whoever beats it is the immediate next
                             # player to act (the one the đền obligation is about).
var foul_finish: int = -1    # player who ended on a deuce ("thối 2"): they DON'T win
                             # and pay the foul penalty. -1 = no foul this deal.
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
	s.chop_level = chop_level
	s.an_trang_winner = an_trang_winner
	s.den_feeder = den_feeder
	s.den_eligible = den_eligible
	s.foul_finish = foul_finish
	s.finished = finished
	s.winner = winner
	return s
