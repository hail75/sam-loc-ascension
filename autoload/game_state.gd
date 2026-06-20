extends Node

## The single runtime path between UI and rules. Holds the pure GameStateData,
## applies every action through SamLocRules, and announces results via signals.
## Contains NO game logic itself — when the authoritative server arrives, only
## this file changes (apply locally -> send over WebSocket, apply the reply).

signal dealt(data: GameStateData)
signal played(player: int, cards: Array, data: GameStateData)
signal passed(player: int, data: GameStateData)
signal rejected(reason: String)
signal match_ended(winner: int, deltas: Array, balances: Array, data: GameStateData)

const START_BALANCE := 1000

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
	dealt.emit(data)

func play(player: int, cards: Array) -> bool:
	return _commit({"type": "play", "player": player, "cards": cards})

func pass_turn(player: int) -> bool:
	return _commit({"type": "pass", "player": player})

func _commit(action: Dictionary) -> bool:
	var r := SamLocRules.apply(data, action)
	if not r.ok:
		rejected.emit(r.reason)
		return false
	data = r.state
	var p: int = action["player"]
	if action["type"] == "play":
		played.emit(p, action["cards"], data)
	else:
		passed.emit(p, data)
	if data.finished:
		_last_winner = data.winner
		var deltas := SamLocRules.settle(data.winner)
		for i in deltas.size():
			balances[i] += deltas[i]
		match_ended.emit(data.winner, deltas, balances, data)
	return true
