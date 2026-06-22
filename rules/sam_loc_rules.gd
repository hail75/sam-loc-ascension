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
##   - a higher QUAD chops a lower QUAD
## Straights run on the order A,2,3,…,10,J,Q,K,A — they may start on an ace or a
## deuce and end no higher than an ace (no wrap past the ace). Leading (an empty
## table) any valid combo is legal. Passing/timing out folds you for the trick.
##
## ĂN TRẮNG (instant win on the deal): some dealt hands win on the spot (deuces
## allowed) — strongest to weakest: three triplets > ten-card straight > five pairs >
## ten-card single-colour flush > quad of deuces. Detected right after the deal (see
## `an_trang_tier` / `an_trang_plays`); the strongest holder wins. Each loser pays a
## flat AN_TRANG_PER stake (see `settle`).
##
## FINISHING ON A DEUCE IS A FOUL (thối 2): a play that empties your hand while still
## holding a 2 is allowed, but you DON'T win — the deal ends, you forfeit the pot and
## pay FINISH_TWO_STAKE to each other player (during báo sâm it fails the declaration).
## Shed your 2s before the final play to actually win.
##
## ĐỀN (block obligation): you đền only when BOTH hold — (1) you play a single that
## ISN'T your highest (you still hold a higher single), and (2) the player with one
## card left beats exactly that single to go out INSTANTLY right after. You then pay
## the đền penalty (see `settle`). Playing your highest single — or leading a combo,
## or any play the one-card player can't instantly beat — never đền.
##
## MONEY (winner-takes-all, all amounts are multiples of STAKE coins):
##   - Normal deal: the winner takes the whole pot — every loser pays 1 stake per
##     card still in hand, plus SPECIAL_STAKE per leftover 2 or quad. A móm loser who
##     never played a card (full HAND_SIZE hand) pays MOM_STAKE extra on the cards.
##   - Đền: the offender (see ĐỀN above) pays their own normal-loss amount to EACH
##     other loser. Settled as a separate beat (the `feed` array from `settle`) just
##     before the pot itself.
##   - Thối 2 (foul finish): no pot is won — the fouler pays FINISH_TWO_STAKE to EACH
##     other player (also via `feed`); no winner-takes-all settle that deal.
##   - Báo sâm: the declarer wins/pays BAO_SAM_PER per opponent (see `settle`).
##   - Chặt (chop): the instant a 2/quad is bombed, the chopped player pays the
##     chopper CHOP_STAKE per chopped 2/quad, times the chop chain's depth (a chop
##     that itself chops a chop pays double, the next triple, …). Chops are
##     immediate side-payments reported in `apply`'s result, NOT part of settle.

const NUM_PLAYERS := 4
const HAND_SIZE := 10
## Money. Every stake below is counted in these units; one unit is STAKE coins.
const STAKE := 10
## Extra stake units a loser pays per leftover 2 or quad still in hand.
const SPECIAL_STAKE := 5
## Extra stake units a "móm" loser pays — one who never played a single card all
## deal and finishes holding their full HAND_SIZE hand (10 stake for the cards → 15).
const MOM_STAKE := 5
## Stake units the báo sâm declarer wins (success) or pays (failure) PER opponent.
const BAO_SAM_PER := 20
## Stake units paid per chopped 2/quad, multiplied by the chop chain's depth.
const CHOP_STAKE := 15
## Stake units a "thối 2" fouler (who emptied their hand on a play holding a deuce)
## pays to EACH other player. They forfeit the win.
const FINISH_TWO_STAKE := 15
## Stake units each opponent pays the ĂN TRẮNG (instant-win) winner — flat, like báo sâm.
const AN_TRANG_PER := 20

## Combo kinds. Order/values are internal; compare only within the same kind.
enum Combo { INVALID, SINGLE, PAIR, TRIPLE, QUAD, STRAIGHT, DOUBLE_QUAD }

## ĂN TRẮNG — a dealt hand that wins on the spot (deuces allowed). Tiers, weakest to
## strongest; a higher value beats a lower one when more than one player qualifies:
##   1 quad of deuces · 2 ten-card single-colour flush · 3 five pairs ·
##   4 ten-card straight · 5 three triplets.
enum AnTrang { NONE, QUAD_TWOS, FLUSH, FIVE_PAIRS, TEN_STRAIGHT, THREE_TRIPLES }

## Sâm Lốc single-rank of a [row, col] card. Sheet cols: 0=A, 1=2, 2=3 … 12=K.
## Order: 3 (low) … 10, J, Q, K, A, 2 (high).
static func rank(card: Array) -> int:
	var col: int = card[1]
	if col == 0:
		return 12  # Ace
	if col == 1:
		return 13  # Two — highest single
	return col - 1

## Per-player balance change for a finished match (winner-takes-all). Returns
## { feed: Array, deltas: Array } — both NUM_PLAYERS-long and zero-sum:
##  * `feed` — the đền (block-obligation) side-penalty, paid out FIRST/separately so
##    the UI can pop it as its own beat before the pot. The offender (the winner's
##    right-hand neighbour, who failed to lead their highest card while the winner
##    held one) pays their own normal-loss amount to EACH other loser. Empty (all
##    zero) when nobody owed it.
##  * `deltas` — the pot itself:
##     - ĂN TRẮNG (instant win on the deal): each loser pays a flat AN_TRANG_PER stake
##       (like báo sâm); the winner sweeps it. Supersedes everything below.
##     - Báo sâm declared: the declarer wins/pays BAO_SAM_PER PER opponent (success →
##       +per each, +3·per total; failure → −per each, −3·per total).
##     - Otherwise: each loser pays 1 stake per card left + SPECIAL_STAKE per leftover
##       2/quad (móm losers pay MOM_STAKE extra), and the winner sweeps the whole pot.
## (Chặt side-payments are settled immediately during play — see `_play` — and are
## NOT included here.)
static func settle(state: GameStateData) -> Dictionary:
	var n := state.hands.size()
	var deltas: Array = []
	var feed: Array = []
	for _p in n:
		deltas.append(0)
		feed.append(0)
	# ĂN TRẮNG (instant win on the deal) supersedes everything: each loser pays a flat
	# AN_TRANG_PER stake (like báo sâm); the winner sweeps it.
	if state.an_trang_winner != -1:
		var w := state.an_trang_winner
		var per := AN_TRANG_PER * STAKE
		for p in n:
			if p == w:
				continue
			deltas[p] = -per
		deltas[w] = (n - 1) * per
		return {"feed": feed, "deltas": deltas}
	if state.bao_sam != -1:
		var success := not state.bao_sam_failed
		var per := BAO_SAM_PER * STAKE
		for p in n:
			if p == state.bao_sam:
				deltas[p] = (n - 1) * per * (1 if success else -1)
			else:
				deltas[p] = per * (-1 if success else 1)
		return {"feed": feed, "deltas": deltas}
	# Thối 2 (foul finish): no pot is won — the fouler pays FINISH_TWO_STAKE to EACH
	# other player and there is no winner-takes-all settle.
	if state.foul_finish != -1:
		var f := state.foul_finish
		for q in n:
			if q == f:
				continue
			feed[q] += FINISH_TWO_STAKE * STAKE
			feed[f] -= FINISH_TWO_STAKE * STAKE
		return {"feed": feed, "deltas": deltas}
	var pot := 0
	for p in n:
		if p == state.winner:
			continue
		var pen := _loss_penalty(state.hands[p])
		deltas[p] = -pen
		pot += pen
	deltas[state.winner] = pot
	# Đền: the player whose single the winner beat to go out instantly, while still
	# holding a higher single (set as `den_feeder` on the winning play), pays their own
	# normal-loss amount to EACH OTHER loser (everyone but the winner and themselves).
	if state.den_feeder != -1:
		var feeder := state.den_feeder
		var pen := _loss_penalty(state.hands[feeder])
		for L in n:
			if L == state.winner or L == feeder:
				continue
			feed[L] += pen
			feed[feeder] -= pen
	return {"feed": feed, "deltas": deltas}

## A loser's pot contribution: 1 stake per leftover card + SPECIAL_STAKE per
## leftover 2 or quad, all in coins. A "móm" loser who never played a card (still
## holds the full HAND_SIZE hand) pays MOM_STAKE extra on the card count.
static func _loss_penalty(hand: Array) -> int:
	var cards := hand.size()
	if cards == HAND_SIZE:
		cards += MOM_STAKE
	return (cards + _special_count(hand) * SPECIAL_STAKE) * STAKE

## Human-facing reasons a loser's normal-loss is inflated, for the UI to caption
## next to the −amount. "CÓNG" — they never played a card (full HAND_SIZE hand).
## "THỐI" — they're stuck with a 2 or a quad. Either, both, or neither may apply.
## (The đền penalty is separate — driven off `settle`'s `feed`, captioned "ĐỀN".)
static func loss_reasons(hand: Array) -> Array:
	var out: Array = []
	if hand.size() == HAND_SIZE:
		out.append("CÓNG")
	if _special_count(hand) > 0:
		out.append("THỐI")
	return out

## Count of leftover deuces plus whole quads in `hand` — each adds a special
## penalty. (Four 2s count as four deuces AND one quad; an extreme edge.)
static func _special_count(hand: Array) -> int:
	var buckets := _buckets(hand)
	var n := 0
	for col in buckets:
		if col == 1:                       # every leftover deuce
			n += buckets[col].size()
		if buckets[col].size() == 4:       # a whole quad still in hand
			n += 1
	return n

## The ĂN TRẮNG tier of a freshly-dealt hand (see AnTrang), or NONE. Checked strongest
## first so the best qualifying combo is returned. Deuces are allowed in any of these.
static func an_trang_tier(hand: Array) -> int:
	if hand.size() != HAND_SIZE:
		return AnTrang.NONE
	var buckets := _buckets(hand)
	# Three triplets: three or more ranks each holding 3+ cards.
	var triples := 0
	for col in buckets:
		if buckets[col].size() >= 3:
			triples += 1
	if triples >= 3:
		return AnTrang.THREE_TRIPLES
	# Ten-card straight: the whole hand is one run.
	if classify(hand).type == Combo.STRAIGHT:
		return AnTrang.TEN_STRAIGHT
	# Five pairs: every rank appears an even number of times, so all 10 cards pair up.
	var all_paired := true
	for col in buckets:
		if buckets[col].size() % 2 != 0:
			all_paired = false
			break
	if all_paired:
		return AnTrang.FIVE_PAIRS
	# Ten same-colour flush: every card the same colour (rows 0–1 red, 2–3 black).
	var flush := true
	var color := _card_color(hand[0])
	for c in hand:
		if _card_color(c) != color:
			flush = false
			break
	if flush:
		return AnTrang.FLUSH
	# Quad of deuces.
	if buckets.has(1) and buckets[1].size() == 4:
		return AnTrang.QUAD_TWOS
	return AnTrang.NONE

## Red (0) for hearts/diamonds (rows 0–1), black (1) for spades/clubs (rows 2–3).
static func _card_color(card: Array) -> int:
	return 0 if card[0] <= 1 else 1

## Every player holding an ĂN TRẮNG combo, as { player, tier }, sorted WEAKEST tier
## first — the animation order; the last (strongest) is the instant winner. Empty if
## nobody qualifies.
static func an_trang_plays(state: GameStateData) -> Array:
	var out: Array = []
	for p in state.hands.size():
		var tier := an_trang_tier(state.hands[p])
		if tier != AnTrang.NONE:
			out.append({"player": p, "tier": tier})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["tier"] < b["tier"])
	return out

## The actual cards that make up the ĂN TRẮNG combo, for the fly-out — only the
## triplet cards / the four 2s for those tiers, the whole hand for the rest (straight,
## five pairs, flush all use all ten).
static func an_trang_cards(hand: Array, tier: int) -> Array:
	var out: Array = []
	match tier:
		AnTrang.THREE_TRIPLES:
			var buckets := _buckets(hand)
			for col in buckets:
				if buckets[col].size() >= 3:
					out.append_array(buckets[col])
			return out
		AnTrang.QUAD_TWOS:
			for c in hand:
				if c[1] == 1:
					out.append(c)
			return out
		_:
			return hand.duplicate(true)

## Deal a fresh match: 10 cards each to `players` players (2–4). `first` leads (the
## previous match's winner; defaults to player 0 for the very first match).
static func deal(rng: RandomNumberGenerator, first: int = 0, players: int = NUM_PLAYERS) -> GameStateData:
	var deck := Deck.make_shuffled(rng)
	var s := GameStateData.new()
	for _p in players:
		s.hands.append([])
		s.passed.append(false)
	for p in players:
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

## Apply an action. Returns { ok: bool, state: GameStateData, reason: String,
## chops: Array }. `chops` (present on a successful play) lists any immediate chặt
## side-payments — each { from, to, amount, level } — for the transport layer to
## apply to balances. On failure the original state is returned unchanged.
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
	for q in ns.hands.size():
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
	# Chặt: if this play bombs the table's 2/quad, record the side-payment and
	# escalate the chop chain (next chop in the trick pays a level higher).
	var chops: Array = []
	var cc := _chop_count(state.table, cards)
	if cc > 0:
		var level := state.chop_level + 1
		ns.chop_level = level
		chops.append({
			"from": state.table_owner,
			"to": p,
			"amount": level * CHOP_STAKE * STAKE * cc,
			"level": level,
		})
	else:
		ns.chop_level = 0

	ns.table = cards.duplicate(true)
	ns.table_owner = p
	# Thối 2 (foul finish): emptying your hand on a play that still holds a deuce is
	# allowed, but you DON'T win — the deal ends, you forfeit the pot and pay the foul
	# penalty (see `settle`). During báo sâm it also means the declaration failed.
	if hand.is_empty() and _has_two(cards):
		ns.finished = true
		ns.winner = -1
		ns.foul_finish = p
		if ns.bao_sam != -1:
			ns.bao_sam_failed = true
		return {"ok": true, "state": ns, "reason": "", "chops": chops}
	# Báo sâm: anyone other than the declarer landing a play means the declarer's
	# lead was beaten — the declaration is broken and the deal ends in failure.
	if ns.bao_sam != -1 and p != ns.bao_sam:
		ns.bao_sam_failed = true
		ns.finished = true
		ns.winner = p
		return {"ok": true, "state": ns, "reason": "", "chops": chops}
	if hand.is_empty():
		ns.finished = true
		ns.winner = p
		# Đền: the winner went out on their last card — a single — beating the table single
		# with NO pass since it was played (`den_eligible`), so they are the immediate next
		# player to act after whoever played it (the seats between had already folded). If
		# that player still holds a HIGHER single, they failed to "play their highest" and
		# the win landed on them: they đền.
		if cards.size() == 1 and state.den_eligible and state.table_owner != p:
			var played_rank := rank(state.table[0])
			for c in state.hands[state.table_owner]:
				if rank(c) > played_rank:
					ns.den_feeder = state.table_owner
					break
		return {"ok": true, "state": ns, "reason": "", "chops": chops}

	# If everyone else has already folded — or the play is intrinsically unbeatable
	# (an ace-high straight, triple 2s, quad 2s: nothing in the deck can answer) — p
	# takes the trick and leads a fresh one. We deliberately do NOT auto-fold players
	# on a merely-can't-be-beaten-right-now read of the hidden hands: every beatable
	# trick is left for each player to answer or pass by hand (the human keeps their
	# turn; bots pass on their timer).
	# A single play arms the đền watch (whoever beats it next, with no pass between, is
	# the immediate next player); any other play disarms it.
	ns.den_eligible = cards.size() == 1
	var nxt := _next_active(ns, p)
	if nxt == p or _is_unbeatable(ns.table):
		_new_trick(ns, p)
	else:
		ns.current = nxt
	return {"ok": true, "state": ns, "reason": "", "chops": chops}

## Does `cards` chop `table`? Returns the count of chopped 2s/quads (0 = no chop):
##   - a QUAD over a single deuce        -> 1
##   - a DOUBLE QUAD over a pair of 2s   -> 2
##   - a higher QUAD over a lower QUAD   -> 1
## (`cards` is assumed to already beat `table`.)
static func _chop_count(table: Array, cards: Array) -> int:
	if table.is_empty():
		return 0
	var ct := classify(table)
	var cp := classify(cards)
	if ct.type == Combo.SINGLE and table[0][1] == 1 and cp.type == Combo.QUAD:
		return 1
	if ct.type == Combo.PAIR and table[0][1] == 1 and cp.type == Combo.DOUBLE_QUAD:
		return 2
	if ct.type == Combo.QUAD and cp.type == Combo.QUAD:
		return 1
	return 0

## True if any card in `cards` is a deuce (col 1).
static func _has_two(cards: Array) -> bool:
	for c in cards:
		if c[1] == 1:
			return true
	return false

## A play that NO possible hand could ever beat — so the trick can end at once
## instead of forcing a pointless round of passes. This is an INTRINSIC property of
## the play (it never peeks at anyone's hand), so it can't auto-fold a player out of
## a trick they could actually answer:
##   - an ace-high straight (top value 14): nothing outranks it at its length
##   - triple 2s: the top triple, and triples can't be chopped
##   - quad 2s: the top quad, and a double-quad only chops a PAIR of 2s
static func _is_unbeatable(table: Array) -> bool:
	if table.is_empty():
		return false
	var c := classify(table)
	var two := rank([0, 1])   # single-rank of a deuce (the highest rank)
	match c.type:
		Combo.STRAIGHT:
			return c.key == 14
		Combo.TRIPLE:
			return c.key == two
		Combo.QUAD:
			return c.key == two
	return false

static func _pass(state: GameStateData, p: int) -> Dictionary:
	var ns := state.clone()
	# A báo sâm declarer only ever acts on their own (empty) lead; passing there
	# means abandoning the open right — the declaration fails immediately.
	if ns.bao_sam == p and ns.table.is_empty():
		ns.bao_sam_failed = true
		ns.finished = true
		ns.winner = _next_active(ns, p)
		return {"ok": true, "state": ns, "reason": ""}
	# Declining an OPEN lead (empty table): no trick has started, so this only hands the
	# open right to the next player — you are NOT folded and still play the trick once
	# someone actually leads a card.
	if ns.table.is_empty():
		ns.current = _next_active(ns, p)
		return {"ok": true, "state": ns, "reason": ""}
	ns.passed[p] = true
	ns.den_eligible = false   # a pass breaks the "immediate next player" đền chain
	# A trick is in progress and only its owner is left standing: they take it
	# and lead a fresh trick (everyone folds back in).
	if ns.table_owner != -1 and _active_count(ns) <= 1:
		_new_trick(ns, ns.table_owner)
	else:
		ns.current = _next_active(ns, p)
	return {"ok": true, "state": ns, "reason": ""}

## Clear the table and refold-reset so `leader` opens a new trick. Ends the chop
## chain (a fresh trick starts at chain depth 0).
static func _new_trick(ns: GameStateData, leader: int) -> void:
	ns.table = []
	ns.table_owner = -1
	ns.chop_level = 0
	ns.den_eligible = false
	for q in ns.hands.size():
		ns.passed[q] = false
	ns.current = leader

static func _active_count(state: GameStateData) -> int:
	var n := 0
	for q in state.hands.size():
		if not state.passed[q]:
			n += 1
	return n

## Next player (counter-clockwise) who hasn't folded this trick. Falls back to
## the immediate next index if everyone has folded (degenerate; can't loop).
static func _next_active(state: GameStateData, p: int) -> int:
	var n := state.hands.size()
	var q := (p + 1) % n
	for _i in n:
		if not state.passed[q]:
			return q
		q = (q + 1) % n
	return (p + 1) % n

static func _index_of(hand: Array, card: Array) -> int:
	for i in hand.size():
		if hand[i][0] == card[0] and hand[i][1] == card[1]:
			return i
	return -1

static func _fail(state: GameStateData, reason: String) -> Dictionary:
	return {"ok": false, "state": state, "reason": reason}

# --- reference bot policy (offline only) ----------------------------------

## A deterministic, heuristic move for `player`: the cards to play, or [] to pass.
## Pure helper for the local bots — NOT authoritative (the future server drives
## real players over the network instead). It plays the new economy:
##   * Going out wins the WHOLE pot, so the bot grabs any legal finisher at once.
##   * Leftover 2s/quads sting (+SPECIAL_STAKE each), so the bot hoards them while
##     it's safe but dumps them once it's short or about to lose.
##   * A chop both pays immediately AND sheds a liability, so the bot spends bombs
##     when a rival is closing in or its own hand is short.
##   * It avoids fouling (emptying the hand on a 2 forfeits the win + pays a penalty),
##     taking the foul only as a last resort when no other lead exists.
static func find_play(state: GameStateData, player: int) -> Array:
	if state.finished or state.current != player or state.passed[player]:
		return []
	var hand: Array = state.hands[player]
	var opp_min := _min_opponent_cards(state, player)
	var my_n := hand.size()
	# The player who will ACT next after us (skips any already folded this trick) — the
	# one the đền obligation is about. On a fresh lead this is just the seat to our left.
	var next_n: int = state.hands[_next_active(state, player)].size()
	if state.table.is_empty():
		return _lead(hand, opp_min, my_n, next_n)
	return _respond(state.table, hand, opp_min, my_n, next_n)

## Fewest cards held by any OTHER player — how close someone is to going out,
## which is when hoarded control becomes worth spending.
static func _min_opponent_cards(state: GameStateData, player: int) -> int:
	var m := 99
	for q in state.hands.size():
		if q != player:
			m = mini(m, state.hands[q].size())
	return m

static func _lead(hand: Array, opp_min: int, my_n: int, next_n: int) -> Array:
	# Win now: the whole hand is one legal combo and isn't an illegal deuce finish.
	if is_valid(hand) and not _has_two(hand):
		return hand.duplicate(true)
	# Đền avoidance: the next player holds one card, so any single we lead, they may
	# beat to win instantly. Lead our HIGHEST single — đền only bites a single that
	# wasn't your highest, so leading the top one is always safe. (Skip only if that
	# highest single would be a foul deuce finish.)
	if next_n == 1:
		var top := _highest_single(hand)
		if not top.is_empty() and not _illegal_finish(hand, [top]):
			return [top]
	# A rival is about to go out: lead the strongest card you can to deny their dump
	# (a 2 is ideal — unbeatable but by a chop). Skip if it's a lone deuce you'd be
	# illegally finishing on.
	if opp_min <= 2:
		var hs := _highest_single(hand)
		if not hs.is_empty() and not _illegal_finish(hand, [hs]):
			return [hs]
	# Otherwise dump the most economical lead: sheds the most, hoards control while
	# it's safe, and offloads 2s/quads once the endgame turns them into liabilities.
	var leads := _legal_leads(hand)
	if leads.is_empty():
		# Only a foul finish remains (e.g. our last card is a lone 2): take it rather
		# than stall the lead — we "thối" and forfeit, but the deal moves on.
		return hand.duplicate(true)
	return _best(leads, hand, opp_min, my_n)

static func _respond(table: Array, hand: Array, opp_min: int, my_n: int, next_n: int) -> Array:
	var legal := _legal_answers(table, hand)
	if legal.is_empty():
		return []
	# Going out takes the whole pot — grab any legal finisher immediately.
	for pl in legal:
		if pl.size() == my_n:
			return pl
	# Đền avoidance: the next player holds one card and the table is a single they
	# might beat to win instantly — answer with our HIGHEST single if it beats, so we
	# never get caught having held a higher one back (which is what đền punishes).
	if next_n == 1 and classify(table).type == Combo.SINGLE:
		var top := _highest_single(hand)
		if not top.is_empty() and beats(table, [top]) and not _illegal_finish(hand, [top]):
			return [top]
	var best := _best(legal, hand, opp_min, my_n)
	if best.is_empty():
		return []
	# Chops pay on the spot AND shed a liability: spend them when a rival is closing
	# in or your own hand is short; sit on the bomb early while nobody threatens.
	if _is_chop(table, best):
		return best if (opp_min <= 3 or my_n <= 6) else []
	# The cheapest answer still burns real control (a 2, or cracking a quad) and
	# nobody is close to out: keep the powder dry and fold this trick.
	if opp_min > 3 and my_n > 5 and _control_cost(hand, best) > 0:
		return []
	return best

## Every legal lead: any combo from the hand that isn't an illegal deuce finish.
static func _legal_leads(hand: Array) -> Array:
	var out: Array = []
	for pl in _enum_all(hand):
		if not _illegal_finish(hand, pl):
			out.append(pl)
	return out

## Every legal answer to `table`: a beating combo (incl. double-quad chops) that
## isn't an illegal deuce finish.
static func _legal_answers(table: Array, hand: Array) -> Array:
	var plays := _enum_all(hand)
	plays.append_array(_enum_double_quads(hand))
	var out: Array = []
	for pl in plays:
		if beats(table, pl) and not _illegal_finish(hand, pl):
			out.append(pl)
	return out

## A play that would empty the hand while it still holds a deuce — a "thối 2" foul
## (legal, but forfeits the win + pays a penalty) the bot avoids by default.
static func _illegal_finish(hand: Array, play: Array) -> bool:
	return play.size() == hand.size() and _has_two(play)

## Pick the lowest-scoring (best) play; [] if there are none.
static func _best(plays: Array, hand: Array, opp_min: int, my_n: int) -> Array:
	var best: Array = []
	var best_score := INF
	for pl in plays:
		if pl.is_empty():
			continue
		var s := _score(hand, pl, opp_min, my_n)
		if best.is_empty() or s < best_score:
			best_score = s
			best = pl
	return best

## Lower = better. Coin-minded: shedding cards is good, dumping end-of-hand
## liabilities (2s/quads) is good when you're losing/short, and spending control
## is bad while you're safe but cheap once it's do-or-die.
static func _score(hand: Array, play: Array, opp_min: int, my_n: int) -> float:
	var s := -float(play.size()) * 6.0                       # shed more cards
	s += float(_control_cost(hand, play)) * _control_weight(opp_min, my_n)
	s -= float(_liability_shed(hand, play)) * _relief_weight(opp_min, my_n)
	s += float(classify(play).key) * 0.2                     # keep the big cards
	return s

## Control burned: deuces and any card off a held quad are winning weapons.
static func _control_cost(hand: Array, play: Array) -> int:
	var counts := {}
	for c in hand:
		counts[c[1]] = int(counts.get(c[1], 0)) + 1
	var used := _buckets(play)
	var cost := 0
	for col in used:
		if col == 1:                              # a deuce
			cost += 8 * used[col].size()
		if int(counts.get(col, 0)) == 4:          # touching a held quad
			cost += 6
	return cost

## Liabilities offloaded: each 2 (and each whole quad) you play dodges its
## SPECIAL_STAKE end penalty. In stake units, so it trades against control directly.
static func _liability_shed(hand: Array, play: Array) -> int:
	var counts := {}
	for c in hand:
		counts[c[1]] = int(counts.get(c[1], 0)) + 1
	var used := _buckets(play)
	var n := 0
	for col in used:
		if col == 1:                                                  # deuces gone
			n += used[col].size()
		if int(counts.get(col, 0)) == 4 and used[col].size() == 4:    # a quad gone
			n += 1
	return n * SPECIAL_STAKE

## Hold control while safe; spend it freely once a rival is near out or your own
## hand is short (do-or-die).
static func _control_weight(opp_min: int, my_n: int) -> float:
	if opp_min <= 2 or my_n <= 4:
		return 1.0
	if opp_min <= 3 or my_n <= 6:
		return 4.0
	return 10.0

## Only bother dumping liabilities when you're likely to LOSE (a rival closing in
## while your hand is still fat) or you're deep in your own endgame.
static func _relief_weight(opp_min: int, my_n: int) -> float:
	if opp_min <= 3 and my_n >= 6:
		return 8.0
	if my_n <= 5:
		return 4.0
	return 0.0

static func _is_chop(table: Array, play: Array) -> bool:
	return _chop_count(table, play) > 0

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
