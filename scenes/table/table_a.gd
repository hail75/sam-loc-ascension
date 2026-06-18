@tool
extends Control

## Screen A — standard in-game table.
## Presentation + input plumbing only: it lays out seats/cards/buttons from a
## static snapshot and reports taps. No Sâm Lốc rules live here; a GameState
## module will feed `populate()` later and receive the play/pass/select intents.

const CardScene: PackedScene = preload("res://scenes/card/card.tscn")

const BASE_W := 720.0
const HAND_W := 100.0         # card width in hand / last-played
const HAND_AVAIL := 664.0     # fan track width
const HAND_MAX_STEP := 66.0
const SELECT_LIFT := 28.0

@onready var _chrome: TableChrome = $Chrome
@onready var _hand: Control = $Hand
@onready var _last_played: Control = $LastPlayedCards
@onready var _play_btn: PixelButton = $PlayButton
@onready var _pass_btn: PixelButton = $PassButton
@onready var _seat_you: Seat = $SeatYou

# --- static mockup snapshot (stands in for GameState) ---
var coins := 12450
var you_count := 10
# Player hand as [row, col] sprite cells (the mockup's deck).
var hand := [[2, 0], [0, 12], [2, 11], [1, 9], [0, 8], [3, 7], [3, 6], [1, 4], [2, 3], [0, 2]]
# Last trick on the table.
var last_played := [[1, 8], [3, 8]]

var _selected: Dictionary = {}

func _ready() -> void:
	_chrome.coins = coins
	_seat_you.hero_name = "YOU · %d" % you_count
	if not Engine.is_editor_hint():
		_play_btn.pressed.connect(_on_play)
		_pass_btn.pressed.connect(_on_pass)
	_rebuild()

# --- layout ---------------------------------------------------------------

## Clear and re-lay the dynamic cards. Safe to call repeatedly (editor reloads).
func _rebuild() -> void:
	for n in _hand.get_children():
		n.free()
	for n in _last_played.get_children():
		n.free()
	_selected.clear()
	_build_last_played()
	_build_hand()

func _build_last_played() -> void:
	# Two overlapping cards, full-size overlap (-28, scaled from the mockup's -14).
	var step := HAND_W - 28.0
	var total := HAND_W + step * (last_played.size() - 1)
	var start := (BASE_W - total) * 0.5
	for i in last_played.size():
		var c := _make_card(last_played[i][0], last_played[i][1])
		c.position = Vector2(start + i * step, 0.0)
		_last_played.add_child(c)

func _build_hand() -> void:
	var cards := hand.duplicate()
	cards.sort_custom(func(a: Array, b: Array) -> bool: return _rank(a[1]) < _rank(b[1]))
	var n := cards.size()
	var step := HAND_MAX_STEP if n <= 1 else minf(HAND_MAX_STEP, (HAND_AVAIL - HAND_W) / (n - 1))
	var total := HAND_W + step * (n - 1)
	var start := (BASE_W - total) * 0.5
	for i in n:
		var c := _make_card(cards[i][0], cards[i][1])
		c.position = Vector2(start + i * step, 0.0)
		c.mouse_filter = Control.MOUSE_FILTER_STOP
		c.gui_input.connect(_on_card_input.bind(c))
		_hand.add_child(c)

func _make_card(row: int, col: int) -> Card:
	var c := CardScene.instantiate() as Card
	c.card_width = int(HAND_W)
	c.row = row
	c.col = col
	return c

## Sâm Lốc rank order (3<4<…<K<A<2). Sheet cols: 0=A, 1=2, 2=3 … 12=K.
func _rank(col: int) -> int:
	if col == 0:
		return 12  # Ace
	if col == 1:
		return 13  # Two (highest)
	return col - 1

# --- input ----------------------------------------------------------------

func _on_card_input(event: InputEvent, card: Card) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var sel := not _selected.get(card, false)
		_selected[card] = sel
		card.position.y = -SELECT_LIFT if sel else 0.0
		card.z_index = 1 if sel else 0

func _selected_cards() -> Array:
	return _selected.keys().filter(func(c: Card) -> bool: return _selected[c])

func _on_play() -> void:
	# Hook for GameState: the player wants to play the selected cards.
	pass

func _on_pass() -> void:
	# Hook for GameState: the player passes.
	pass
