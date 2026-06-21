extends Node

## The single runtime path between UI and rules. Holds the pure GameStateData,
## applies every action through SamLocRules, and announces results via signals.
## Contains NO game logic itself — when the authoritative server arrives, only
## this file changes (apply locally -> send over WebSocket, apply the reply).

signal dealt(data: GameStateData)
signal played(player: int, cards: Array, data: GameStateData)
signal passed(player: int, data: GameStateData)
signal declared(player: int, data: GameStateData)
signal rejected(reason: String)
## A chặt (chop) side-payment landed: `from_player` paid `to_player` `amount` coins
## (balances already updated). Emitted right after the `played` that caused it.
signal chopped(from_player: int, to_player: int, amount: int, balances: Array)
## The deal is over. `feed` is the đền (block-obligation) side-penalty paid out
## first as its own beat (all-zero when nobody owed it); `deltas` is the pot itself.
## `balances` already reflects both.
signal match_ended(winner: int, deltas: Array, feed: Array, balances: Array, data: GameStateData)

const START_BALANCE := 8080

## DEBUG: force Vayne (seat 2) to hold the four 2s every deal, so the ĂN TRẮNG
## (instant-win) flow fires every match. Turn OFF for real play.
const AN_TRANG_DEBUG := false
const AN_TRANG_DEBUG_SEAT := 2

var data: GameStateData
var balances: Array = []          # persistent per-player money, survives re-deals
var _last_winner := 0             # leads the next deal; player 0 for match one
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	for _p in SamLocRules.NUM_PLAYERS:
		balances.append(START_BALANCE)

## Start (or restart) a match and deal fresh hands; last match's winner leads.
func new_match() -> void:
	data = SamLocRules.deal(_rng, _last_winner)
	if AN_TRANG_DEBUG:
		_debug_force_quad_deuces(AN_TRANG_DEBUG_SEAT)
	# ĂN TRẮNG: if anyone was dealt an instant-win hand, the strongest wins on the spot.
	# Set up the win now (so the table can animate it) but defer the money to
	# commit_an_trang(), called once the table reaches the +/- beat.
	var plays := SamLocRules.an_trang_plays(data)
	if not plays.is_empty():
		var w: int = plays.back()["player"]
		data.an_trang_winner = w
		data.winner = w
		data.finished = true
		_last_winner = w
	dealt.emit(data)

## Apply the deferred ĂN TRẮNG settle to balances; returns { deltas, balances } for
## the table's +/- pops. Call exactly once, when the win beat is shown.
func commit_an_trang() -> Dictionary:
	var s := SamLocRules.settle(data)
	var deltas: Array = s["deltas"]
	for i in deltas.size():
		balances[i] += deltas[i]
	return {"deltas": deltas, "balances": balances.duplicate()}

## DEBUG helper: rebuild the hands so `seat` holds all four 2s. The 52-card deck only
## deals 40, so some 2s may be undealt — inject all four explicitly (col 1, every
## suit) and fill from the dealt NON-deuce cards. Keeps every hand at HAND_SIZE.
func _debug_force_quad_deuces(seat: int) -> void:
	var deuces: Array = [[0, 1], [1, 1], [2, 1], [3, 1]]
	var pool: Array = []
	for p in SamLocRules.NUM_PLAYERS:
		for c in data.hands[p]:
			if c[1] != 1:
				pool.append(c)
	var hands: Array = []
	for _p in SamLocRules.NUM_PLAYERS:
		hands.append([])
	hands[seat].append_array(deuces)
	for _i in (SamLocRules.HAND_SIZE - deuces.size()):
		hands[seat].append(pool.pop_back())
	for p in SamLocRules.NUM_PLAYERS:
		if p == seat:
			continue
		for _i in SamLocRules.HAND_SIZE:
			hands[p].append(pool.pop_back())
	data.hands = hands

func play(player: int, cards: Array) -> bool:
	return _commit({"type": "play", "player": player, "cards": cards})

func pass_turn(player: int) -> bool:
	return _commit({"type": "pass", "player": player})

## Declare báo sâm: `player` grabs the open right for this deal.
func declare_bao_sam(player: int) -> bool:
	return _commit({"type": "declare", "player": player})

func _commit(action: Dictionary) -> bool:
	var r := SamLocRules.apply(data, action)
	if not r.ok:
		rejected.emit(r.reason)
		return false
	data = r.state
	var p: int = action["player"]
	match action["type"]:
		"play":
			played.emit(p, action["cards"], data)
			# Settle any chặt side-payments this play triggered, then announce each
			# so the table can pop the +/- amount over the two seats.
			for chop in r.get("chops", []):
				balances[chop["from"]] -= chop["amount"]
				balances[chop["to"]] += chop["amount"]
				chopped.emit(chop["from"], chop["to"], chop["amount"], balances)
		"declare":
			declared.emit(p, data)
		_:
			passed.emit(p, data)
	if data.finished:
		_last_winner = data.winner
		var s := SamLocRules.settle(data)
		var feed: Array = s["feed"]
		var deltas: Array = s["deltas"]
		# Apply the đền side-penalty first, then the pot — so balances are final, and
		# the table can pop `feed` as its own beat ahead of `deltas`.
		for i in feed.size():
			balances[i] += feed[i]
		for i in deltas.size():
			balances[i] += deltas[i]
		match_ended.emit(data.winner, deltas, feed, balances, data)
	return true
