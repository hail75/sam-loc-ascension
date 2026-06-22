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

const START_BALANCE := 1000

## DEBUG: force Vayne (seat 2) to hold a fixed ĂN TRẮNG hand every deal so the
## instant-win flow fires every match. Turn OFF for real play. The forced hand is
## [row, col] cards (col: 0=A,1=2,2=3…12=K). Current: a ten-card straight A→10
## (cols 0–9), mixed suits → "SẢNH RỒNG".
## DEBUG: start the session with one bot already kicked (3 players) to eyeball the
## shrunk layout without playing a bot broke first. OFF for real play.
const DEBUG_KICK_ONE := false
const AN_TRANG_DEBUG := false
const AN_TRANG_DEBUG_SEAT := 2
const AN_TRANG_DEBUG_HAND := [
	[0, 0], [1, 1], [2, 2], [3, 3], [0, 4],
	[1, 5], [2, 6], [3, 7], [0, 8], [1, 9],
]

var data: GameStateData
var balances: Array = []          # per-player money (one per LIVE player), survives re-deals
var num_players := SamLocRules.NUM_PLAYERS   # live players this session (shrinks as bots bust)
var _last_winner := 0             # leads the next deal; player 0 for match one
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	if DEBUG_KICK_ONE:
		num_players = SamLocRules.NUM_PLAYERS - 1   # start at 3 players
	for _p in num_players:
		balances.append(START_BALANCE)

## Start (or restart) a match and deal fresh hands; last match's winner leads.
func new_match() -> void:
	_apply_elimination()
	if _last_winner < 0 or _last_winner >= num_players:
		_last_winner = 0
	data = SamLocRules.deal(_rng, _last_winner, num_players)
	if AN_TRANG_DEBUG:
		_debug_force_hand(AN_TRANG_DEBUG_SEAT, AN_TRANG_DEBUG_HAND)
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

## Before a fresh deal: bust out broke bots (re-indexing the survivors). YOU (player 0)
## never leave — if you're broke, or only you'd remain, the whole table resets to a
## fresh 4 players at START_BALANCE.
func _apply_elimination() -> void:
	if balances[0] <= 0:
		_reset_all()
		return
	var kept: Array = []
	for p in num_players:
		if p == 0 or balances[p] > 0:
			kept.append(p)
	if kept.size() <= 1:
		_reset_all()      # only you left → fresh table
		return
	if kept.size() == num_players:
		return            # nobody busted
	var new_bal: Array = []
	var nw := 0
	for i in kept.size():
		new_bal.append(balances[kept[i]])
		if kept[i] == _last_winner:
			nw = i
	balances = new_bal
	num_players = kept.size()
	_last_winner = nw

## Reset to a full 4-player table at START_BALANCE.
func _reset_all() -> void:
	num_players = SamLocRules.NUM_PLAYERS
	balances = []
	for _p in num_players:
		balances.append(START_BALANCE)
	_last_winner = 0

## Apply the deferred ĂN TRẮNG settle to balances; returns { deltas, balances } for
## the table's +/- pops. Call exactly once, when the win beat is shown.
func commit_an_trang() -> Dictionary:
	var s := SamLocRules.settle(data)
	var deltas: Array = s["deltas"]
	for i in deltas.size():
		balances[i] += deltas[i]
	return {"deltas": deltas, "balances": balances.duplicate()}

## DEBUG helper: rebuild the hands so `seat` holds exactly `forced` ([row, col] cards),
## filling the rest from the dealt cards that aren't in `forced`. The 52-card deck only
## deals 40, so some forced cards may be undealt — they're injected explicitly. Keeps
## every hand at HAND_SIZE.
func _debug_force_hand(seat: int, forced: Array) -> void:
	var n := data.hands.size()
	var pool: Array = []
	for p in n:
		for c in data.hands[p]:
			var is_forced := false
			for f in forced:
				if f[0] == c[0] and f[1] == c[1]:
					is_forced = true
					break
			if not is_forced:
				pool.append(c)
	var hands: Array = []
	for _p in n:
		hands.append([])
	hands[seat].append_array(forced.duplicate(true))
	for _i in (SamLocRules.HAND_SIZE - forced.size()):
		hands[seat].append(pool.pop_back())
	for p in n:
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
