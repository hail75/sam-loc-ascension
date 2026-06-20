class_name SamLocRules
extends RefCounted

## The engine: (state, action) -> new state. Pure, static, self-contained —
## no Node, no UI, no signals. The single place game logic lives, so it can move
## to the Python/FastAPI server later without touching the client.
##
## COMBOS (this build): single, pair, triple, quad, and straight (run of >=3).
## A response must match the table combo's TYPE and SIZE and outrank its key,
## except for chops:
##   - a QUAD chops a single deuce          (1 quad  > 1 two)
##   - a DOUBLE QUAD chops a pair of deuces  (2 quads > 2 twos)
## Straights run on the order A,2,3,…,10,J,Q,K,A — they may start on an ace or a
## deuce and end no higher than an ace (no wrap past the ace). Leading (an empty
## table) any valid combo is legal. Passing/timing out folds you for the trick.

const NUM_PLAYERS := 4
const HAND_SIZE := 10
const WIN_REWARD := 30
const LOSS_PENALTY := 10
## Báo sâm stakes: the declarer takes (or pays) this much PER opponent.
const BAO_SAM_STAKE := 20

## Combo kinds. Order/values are internal; compare only within the same kind.
enum Combo { INVALID, SINGLE, PAIR, TRIPLE, QUAD, STRAIGHT, DOUBLE_QUAD }

## Sâm Lốc single-rank of a [row, col] card. Sheet cols: 0=A, 1=2, 2=3 … 12=K.
## Order: 3 (low) … 10, J, Q, K, A, 2 (high).
static func rank(card: Array) -> int:
	var col: int = card[1]
	if col == 0:
		return 12  # Ace
	if col == 1:
		return 13  # Two — highest single
	return col - 1

## Per-player balance change for a finished match.
##  * Báo sâm declared: the declarer wins/pays the stake against EACH opponent
##    (+20 each on success, -20 each on failure); opponents take the other side.
##  * Otherwise: the winner gains, the losers each pay.
static func settle(state: GameStateData) -> Array:
	var deltas: Array = []
	if state.bao_sam != -1:
		var success := not state.bao_sam_failed
		for p in NUM_PLAYERS:
			if p == state.bao_sam:
				deltas.append(BAO_SAM_STAKE * (NUM_PLAYERS - 1) * (1 if success else -1))
			else:
				deltas.append(BAO_SAM_STAKE * (-1 if success else 1))
		return deltas
	for p in NUM_PLAYERS:
		deltas.append(WIN_REWARD if p == state.winner else -LOSS_PENALTY)
	return deltas

## Deal a fresh match: 10 cards each. `first` leads (the previous match's winner;
## defaults to player 0 for the very first match).
static func deal(rng: RandomNumberGenerator, first: int = 0) -> GameStateData:
	var deck := Deck.make_shuffled(rng)
	var s := GameStateData.new()
	for _p in NUM_PLAYERS:
		s.hands.append([])
		s.passed.append(false)
	for p in NUM_PLAYERS:
		for _i in HAND_SIZE:
			s.hands[p].append(deck.pop_back())
	s.current = first
	return s

# --- combo classification -------------------------------------------------

## Identify a set of cards: { type: Combo, size: int, key: int }. `key` ranks
## plays of the same type (singles/pairs/etc. by card rank; straights by their
## top value). INVALID for anything illegal.
static func classify(cards: Array) -> Dictionary:
	var n := cards.size()
	if n == 0:
		return {"type": Combo.INVALID, "size": 0, "key": -1}
	var buckets := _buckets(cards)
	# All one rank -> single / pair / triple / quad.
	if buckets.size() == 1:
		match n:
			1: return {"type": Combo.SINGLE, "size": 1, "key": rank(cards[0])}
			2: return {"type": Combo.PAIR, "size": 2, "key": rank(cards[0])}
			3: return {"type": Combo.TRIPLE, "size": 3, "key": rank(cards[0])}
			4: return {"type": Combo.QUAD, "size": 4, "key": rank(cards[0])}
		return {"type": Combo.INVALID, "size": 0, "key": -1}
	# Two ranks, each a full quad -> the double-quad bomb (chops a pair of 2s).
	if n == 8 and buckets.size() == 2:
		var top := -1
		var all_quads := true
		for col in buckets:
			if buckets[col].size() != 4:
				all_quads = false
				break
			top = maxi(top, rank([0, col]))
		if all_quads:
			return {"type": Combo.DOUBLE_QUAD, "size": 8, "key": top}
	# All distinct ranks, length >=3 -> maybe a straight.
	if buckets.size() == n and n >= 3:
		var t := _straight_top(cards)
		if t != -1:
			return {"type": Combo.STRAIGHT, "size": n, "key": t}
	return {"type": Combo.INVALID, "size": 0, "key": -1}

static func is_valid(cards: Array) -> bool:
	return classify(cards).type != Combo.INVALID

## Does `play` beat `table` (both already on the table / proposed)?
static func beats(table: Array, play: Array) -> bool:
	var cp: Dictionary = classify(play)
	if cp.type == Combo.INVALID:
		return false
	var ct: Dictionary = classify(table)
	# Chops: quads bomb deuces regardless of type match.
	if ct.type == Combo.SINGLE and table[0][1] == 1:
		return cp.type == Combo.QUAD
	if ct.type == Combo.PAIR and table[0][1] == 1:
		return cp.type == Combo.DOUBLE_QUAD
	# Otherwise: same kind, same length, higher key.
	if cp.type != ct.type or cp.size != ct.size:
		return false
	return cp.key > ct.key

## Straight value of a card: A,2,3,…,K,A. Ace is low (1) or high (14); 2…K are
## fixed (2…13). Returns the run's top value if `cards` form a straight, else -1.
static func _straight_top(cards: Array) -> int:
	var has_ace := false
	for c in cards:
		if c[1] == 0:
			has_ace = true
	# A straight holds at most one ace, so try it low then high.
	for ace_high in [false, true]:
		if ace_high and not has_ace:
			continue
		var vals: Array = []
		for c in cards:
			vals.append(_straight_val(c[1], ace_high))
		vals.sort()
		var ok := true
		for i in range(1, vals.size()):
			if vals[i] != vals[i - 1] + 1:
				ok = false
				break
		if ok:
			return vals[vals.size() - 1]
	return -1

static func _straight_val(col: int, ace_high: bool) -> int:
	if col == 0:
		return 14 if ace_high else 1
	return col + 1   # 2->2, 3->3, … K->13

static func _buckets(cards: Array) -> Dictionary:
	var b := {}
	for c in cards:
		var col: int = c[1]
		if not b.has(col):
			b[col] = []
		b[col].append(c)
	return b

# --- actions --------------------------------------------------------------

## Apply an action. Returns { ok: bool, state: GameStateData, reason: String }.
## On failure the original state is returned unchanged.
static func apply(state: GameStateData, action: Dictionary) -> Dictionary:
	if state.finished:
		return _fail(state, "match over")
	var p: int = action.get("player", -1)
	# Declaring báo sâm happens before the normal turn order kicks in, so it is
	# allowed off-turn (any player may grab the open right pre-play).
	if action.get("type", "") == "declare":
		return _declare(state, p)
	if p != state.current:
		return _fail(state, "not your turn")
	if state.passed[p]:
		return _fail(state, "you folded this trick")

	match action.get("type", ""):
		"play":
			return _play(state, p, action.get("cards", []))
		"pass":
			return _pass(state, p)
		_:
			return _fail(state, "unknown action")

## Claim the báo sâm: `p` declares, takes the open right, and leads at once.
## Only valid before any card has been played this deal.
static func _declare(state: GameStateData, p: int) -> Dictionary:
	if state.bao_sam != -1:
		return _fail(state, "báo sâm already declared")
	if not state.table.is_empty():
		return _fail(state, "too late to báo sâm")
	var ns := state.clone()
	ns.bao_sam = p
	ns.current = p
	ns.table_owner = -1
	for q in NUM_PLAYERS:
		ns.passed[q] = false
	return {"ok": true, "state": ns, "reason": ""}

static func _play(state: GameStateData, p: int, cards: Array) -> Dictionary:
	if not is_valid(cards):
		return _fail(state, "not a valid combo")
	# Answering the table: the play must beat it (chops included).
	if not state.table.is_empty() and not beats(state.table, cards):
		return _fail(state, "doesn't beat the table")
	var ns := state.clone()
	var hand: Array = ns.hands[p]
	for c in cards:
		var idx := _index_of(hand, c)
		if idx == -1:
			return _fail(state, "card not in hand")
		hand.remove_at(idx)
	ns.table = cards.duplicate(true)
	ns.table_owner = p
	# Báo sâm: anyone other than the declarer landing a play means the declarer's
	# lead was beaten — the declaration is broken and the deal ends in failure.
	if ns.bao_sam != -1 and p != ns.bao_sam:
		ns.bao_sam_failed = true
		ns.finished = true
		ns.winner = p
		return {"ok": true, "state": ns, "reason": ""}
	if hand.is_empty():
		ns.finished = true
		ns.winner = p
		return {"ok": true, "state": ns, "reason": ""}

	# If everyone else has already folded, p takes the trick and leads anew.
	var nxt := _next_active(ns, p)
	if nxt == p:
		_new_trick(ns, p)
	else:
		ns.current = nxt
	return {"ok": true, "state": ns, "reason": ""}

static func _pass(state: GameStateData, p: int) -> Dictionary:
	var ns := state.clone()
	# A báo sâm declarer only ever acts on their own (empty) lead; passing there
	# means abandoning the open right — the declaration fails immediately.
	if ns.bao_sam == p and ns.table.is_empty():
		ns.bao_sam_failed = true
		ns.finished = true
		ns.winner = _next_active(ns, p)
		return {"ok": true, "state": ns, "reason": ""}
	ns.passed[p] = true
	# A trick is in progress and only its owner is left standing: they take it
	# and lead a fresh trick (everyone folds back in).
	if ns.table_owner != -1 and _active_count(ns) <= 1:
		_new_trick(ns, ns.table_owner)
	else:
		ns.current = _next_active(ns, p)
	return {"ok": true, "state": ns, "reason": ""}

## Clear the table and refold-reset so `leader` opens a new trick.
static func _new_trick(ns: GameStateData, leader: int) -> void:
	ns.table = []
	ns.table_owner = -1
	for q in NUM_PLAYERS:
		ns.passed[q] = false
	ns.current = leader

static func _active_count(state: GameStateData) -> int:
	var n := 0
	for q in NUM_PLAYERS:
		if not state.passed[q]:
			n += 1
	return n

## Next player (counter-clockwise) who hasn't folded this trick. Falls back to
## the immediate next index if everyone has folded (degenerate; can't loop).
static func _next_active(state: GameStateData, p: int) -> int:
	var q := (p + 1) % NUM_PLAYERS
	for _i in NUM_PLAYERS:
		if not state.passed[q]:
			return q
		q = (q + 1) % NUM_PLAYERS
	return (p + 1) % NUM_PLAYERS

static func _index_of(hand: Array, card: Array) -> int:
	for i in hand.size():
		if hand[i][0] == card[0] and hand[i][1] == card[1]:
			return i
	return -1

static func _fail(state: GameStateData, reason: String) -> Dictionary:
	return {"ok": false, "state": state, "reason": reason}

# --- reference bot policy (offline only) ----------------------------------

## A deterministic, heuristic move for `player`: the cards to play, or [] to
## pass. Pure helper for the local bots — NOT part of the authoritative rules
## (the future server drives real players over the network instead).
##
## The heuristic, in one breath: shed cheap cards, hoard control (2s and quads),
## and only spend that control when an opponent is about to go out. Concretely —
##   * Leading: dump your lowest non-control combo (longest straights first, to
##     thin the hand fastest); but if a rival is down to <=2 cards, slam your
##     highest single so they can't dump on your lead.
##   * Following: among every legal answer, take the one that wastes the least
##     control while shedding the most. If even the cheapest answer means burning
##     a 2 or cracking a quad and nobody is close to winning, fold instead.
##   * Quad/double-quad chops on deuces are saved unless a rival is near out.
##   * Going out: if the whole hand is one legal combo, play it and win.
static func find_play(state: GameStateData, player: int) -> Array:
	if state.finished or state.current != player or state.passed[player]:
		return []
	var hand: Array = state.hands[player]
	var opp_min := _min_opponent_cards(state, player)
	if state.table.is_empty():
		return _lead(hand, opp_min)
	return _respond(state.table, hand, opp_min)

## Fewest cards held by any OTHER player — how close the table is to someone
## going out, which is when hoarded control becomes worth spending.
static func _min_opponent_cards(state: GameStateData, player: int) -> int:
	var m := 99
	for q in NUM_PLAYERS:
		if q != player:
			m = mini(m, state.hands[q].size())
	return m

static func _lead(hand: Array, opp_min: int) -> Array:
	# Whole hand is one combo -> go out now and win.
	if hand.size() >= 1 and is_valid(hand):
		return hand.duplicate(true)
	# A rival is about to go out: lead something they can't beat to deny a dump.
	if opp_min <= 2:
		var high := _highest_single(hand)
		return [high] if not high.is_empty() else []
	# Otherwise dump the cheapest combo (cheapest = sheds most, hoards control).
	return _best(_enum_all(hand), hand)

static func _respond(table: Array, hand: Array, opp_min: int) -> Array:
	var plays := _enum_all(hand)
	plays.append_array(_enum_double_quads(hand))   # for chopping a pair of 2s
	var legal: Array = []
	for pl in plays:
		if beats(table, pl):
			legal.append(pl)
	if legal.is_empty():
		return []
	var best := _best(legal, hand)
	# Hold chops (quad / double-quad on deuces) unless a rival is near out.
	if _is_chop(table, best) and opp_min > 3:
		return []
	# Cheapest legal answer still costs control (a 2, or cracking a quad) and
	# nobody is close to winning: keep the powder dry and fold this trick.
	if opp_min > 3 and _control_cost(hand, best) > 0:
		return []
	return best

## Pick the play with the lowest cost (best). [] if there are no candidates.
static func _best(plays: Array, hand: Array) -> Array:
	var best: Array = []
	var best_score := INF
	for pl in plays:
		if pl.is_empty():
			continue
		var s := _score(hand, pl)
		if best.is_empty() or s < best_score:
			best_score = s
			best = pl
	return best

## Lower is better: control spent dominates, then prefer shedding more cards,
## then prefer a lower rank (keep the big stuff in hand).
static func _score(hand: Array, play: Array) -> float:
	var key: int = classify(play).key
	return _control_cost(hand, play) * 10.0 - play.size() * 5.0 + float(key)

## How much "control" a play burns: deuces are precious, and touching a quad you
## hold (to play a single/pair/triple/quad off it) throws away a future chop.
static func _control_cost(hand: Array, play: Array) -> int:
	var counts := {}
	for c in hand:
		counts[c[1]] = int(counts.get(c[1], 0)) + 1
	var used := _buckets(play)
	var cost := 0
	for col in used:
		if col == 1:                              # a deuce
			cost += 80 * used[col].size()
		if int(counts.get(col, 0)) == 4:          # spending any card of a held quad
			cost += 60
	return cost

static func _is_chop(table: Array, play: Array) -> bool:
	var ct: Dictionary = classify(table)
	if ct.type == Combo.SINGLE and table[0][1] == 1:
		return classify(play).type == Combo.QUAD
	if ct.type == Combo.PAIR and table[0][1] == 1:
		return classify(play).type == Combo.DOUBLE_QUAD
	return false

static func _highest_single(hand: Array) -> Array:
	var best: Array = []
	for c in hand:
		if best.is_empty() or rank(c) > rank(best):
			best = c
	return best

## Every combo playable straight out of `hand`: singles, pairs/triples/quads, and
## all straights. Candidates may overlap; `_best` just scores and picks one.
static func _enum_all(hand: Array) -> Array:
	var out: Array = []
	for c in hand:
		out.append([c])
	var buckets := _buckets(hand)
	for col in buckets:
		var grp: Array = buckets[col]
		for size in [2, 3, 4]:
			if grp.size() >= size:
				out.append(grp.slice(0, size))
	out.append_array(_enum_straights(hand))
	return out

## All straights (length >= 3) that can be formed from `hand`, one card per rank.
static func _enum_straights(hand: Array) -> Array:
	var have := {}
	for c in hand:
		if not have.has(c[1]):
			have[c[1]] = c
	var out: Array = []
	for length in range(3, 14):           # 3..13 cards
		for top in range(length, 15):     # top value, ace-high tops out at 14
			var run: Array = []
			var ok := true
			for v in range(top - length + 1, top + 1):
				if v < 1:
					ok = false
					break
				var col := _val_to_col(v)
				if have.has(col):
					run.append(have[col])
				else:
					ok = false
					break
			if ok and run.size() == length:
				out.append(run)
	return out

## Every pair of held quads, as an 8-card double-quad bomb.
static func _enum_double_quads(hand: Array) -> Array:
	var buckets := _buckets(hand)
	var quads: Array = []
	for col in buckets:
		if buckets[col].size() >= 4:
			quads.append(col)
	var out: Array = []
	for i in quads.size():
		for j in range(i + 1, quads.size()):
			var p: Array = []
			p.append_array(buckets[quads[i]].slice(0, 4))
			p.append_array(buckets[quads[j]].slice(0, 4))
			out.append(p)
	return out

static func _val_to_col(v: int) -> int:
	if v == 1 or v == 14:
		return 0   # ace, low or high
	return v - 1   # 2->1, 3->2, … K->12
