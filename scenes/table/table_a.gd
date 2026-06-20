@tool
extends Control

## Screen A — playable animation-test table: you vs 3 bots.
## Presentation + input plumbing only. All match state lives in the GameState
## autoload (backed by the pure SamLocRules engine); this script just renders
## the state, reports the player's taps, and drives the bot turns on timers so
## the deal / play / win / re-deal animations can be watched.

const CardScene: PackedScene = preload("res://scenes/card/card.tscn")
const DECK_TEX: Texture2D = preload("res://assets/cards/deck_stack.png")
## Deck thinning states, full -> single card, stepped through as it deals.
const DECK_STATES: Array[Texture2D] = [
	preload("res://assets/cards/deck_stack.png"),
	preload("res://assets/cards/deck_stack_1.png"),
	preload("res://assets/cards/deck_stack_2.png"),
	preload("res://assets/cards/deck_stack_3.png"),
	preload("res://assets/cards/deck_stack_4.png"),
]

const BASE_W := 720.0
const HAND_W := 100.0                      # card width in hand / last-played
const CARD_H := HAND_W * 64.0 / 48.0       # matches the sheet cell aspect
const HAND_AVAIL := 664.0                  # fan track width
const HAND_MAX_STEP := 66.0
const LP_OVERLAP := 28.0                   # last-played card overlap
const SELECT_LIFT := 28.0

const TURN_TIME := 20.0                     # seconds a turn (and the báo sâm window) lasts; the seat ring drains over this for everyone
const BOT_DELAY_MIN := 1.5                  # bots act somewhere inside their turn
const BOT_DELAY_MAX := 4.0
const FLY_TIME := 0.32                      # play-to-centre flight
const WIN_PAUSE := 1.6                      # hold on the winner before re-dealing
const DEAL_FLIGHT := 0.26                   # one card's deck->seat flight (longer = smoother)
const DEAL_STAGGER := 0.045                 # gap between dealt cards (shorter = faster overall)
const FLIP_TIME := 0.16                     # your cards flipping face-up

@onready var _chrome: TableChrome = $Chrome
@onready var _hand: Control = $Hand
@onready var _last_played: Control = $LastPlayedCards
@onready var _play_btn: PixelButton = $PlayButton
@onready var _pass_btn: PixelButton = $PassButton

# Player index -> seat. Indices ascend counter-clockwise from the player:
# 0 YOU (bottom) -> 1 (right) -> 2 (top) -> 3 (left).
@onready var _seats: Dictionary = {
	0: $SeatYou,
	1: $SeatGrimwald,
	2: $SeatVayne,
	3: $SeatSeraphine,
}

const POP_FONT: Font = preload("res://assets/fonts/dearpix.ttf")
const POP_GOLD := Color("f0d68a")     # winner gain
const POP_GREY := Color("9d978d")     # loser loss (muted)

var last_played: Array = []        # cards currently resting on the table
var _selected: Dictionary = {}     # Card -> bool
var _my_turn := false
var _bao_window := false            # the báo sâm claim window is open (buttons mean claim/thôi)
var _bao_passed: Array = []         # during the window: which of the 4 have thôi'd (declined)
var _gen := 0                      # bumped each deal; cancels stale bot/timeout awaits
var _turn_tween: Tween
var _pending_origins: Array = []   # global centres of the cards you just played
var _deck: TextureRect             # the stacked-deck sprite shown while dealing
var _deck_shadow: TextureRect      # its drop shadow (same look as the cards')
var _deck_bottom: Vector2          # fixed bottom-centre the deck is anchored to

func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_preview()
		return
	# Set the button copy/size here (not just in the .tscn) so it survives the
	# Godot editor re-saving the scene over our changes.
	_play_btn.text = "ĐÁNH"
	_play_btn.font_size = 54
	_pass_btn.text = "THÔI"
	_pass_btn.font_size = 54
	_play_btn.pressed.connect(_on_play)
	_pass_btn.pressed.connect(_on_pass)
	GameState.dealt.connect(_on_dealt)
	GameState.played.connect(_on_played)
	GameState.passed.connect(_on_passed)
	GameState.match_ended.connect(_on_match_ended)
	GameState.rejected.connect(_on_rejected)
	resized.connect(_relayout)
	_relayout.call_deferred()   # after first layout pass, so seat sizes are valid
	GameState.new_match()

## Vietnamese player-facing copy for each engine rejection reason.
const WARN_VI := {
	"not a valid combo": "Bộ bài không hợp lệ",
	"doesn't beat the table": "Bài không đủ lớn",
	"card not in hand": "Bài không có trong tay",
	"you folded this trick": "Bạn đã bỏ lượt này",
	"not your turn": "Chưa tới lượt bạn",
}

## Only the human's plays get rejected (bots only ever submit legal moves), so a
## rejection while it's your turn means your selection was illegal — warn softly.
func _on_rejected(reason: String) -> void:
	if not _my_turn:
		return
	_warn(WARN_VI.get(reason, "Nước đi không hợp lệ"))

## Small white warning that pops above the buttons and fades out.
func _warn(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", POP_FONT)
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Palette.OUTLINE)
	lbl.add_theme_constant_override("outline_size", 8)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(_vw(), 0.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 12
	lbl.position = Vector2(0.0, size.y - 360.0)
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 60.0, 1.1) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.1).set_ease(Tween.EASE_IN)
	tw.finished.connect(lbl.queue_free)

# --- match flow -----------------------------------------------------------

func _on_dealt(data: GameStateData) -> void:
	_gen += 1
	var g := _gen
	# Reset the table to empty and hide the count badges while we deal.
	last_played = []
	_rebuild_last_played()
	for n in _hand.get_children():
		n.free()
	_selected.clear()
	for p in _seats:
		_seats[p].active = false
		_seats[p].card_count = 0
		_seats[p].show_badge = false
		_seats[p].balance = GameState.balances[p]
	# The action button advertises the upcoming claim while dealing (greyed-out
	# BÁO SÂM, not ĐÁNH), since the báo sâm window comes before any normal turn.
	_play_btn.text = "BÁO SÂM"
	_pass_btn.text = "THÔI"
	_set_my_turn(false)
	_chrome.banner_text = "ĐANG CHIA BÀI"

	await _deal_animation(data, g)
	if g != _gen:
		return   # a newer deal superseded this one

	for p in _seats:
		_seats[p].card_count = data.hands[p].size()
		_seats[p].show_badge = true
	# The "special turn" before play: a window to claim báo sâm. May change the
	# state (declarer leads), so read GameState.data fresh afterwards.
	await _bao_sam_window(g)
	if g != _gen:
		return
	_start_turn(GameState.data)

## Fling card backs from the deck stack to every player, counter-clockwise,
## then flip your own hand face-up. Awaitable; bails if `g` goes stale.
func _deal_animation(data: GameStateData, g: int) -> void:
	var deck_centre := _last_played.global_position + Vector2(_vw() * 0.5, CARD_H * 0.5)
	_show_deck(deck_centre)
	var deck_tl := deck_centre - Vector2(HAND_W, CARD_H) * 0.5
	var slots := _hand_slot_positions()   # your final fan, global top-left per card
	var your_backs: Array = []
	var hi := 0
	var total := SamLocRules.HAND_SIZE * SamLocRules.NUM_PLAYERS
	var dealt := 0

	for _round in SamLocRules.HAND_SIZE:
		for p in [0, 1, 2, 3]:
			if g != _gen:
				return
			var back := _make_back()
			back.z_index = 7
			back.position = deck_tl
			add_child(back)
			var target: Vector2
			if p == 0:
				target = slots[hi]
				hi += 1
				your_backs.append(back)
			else:
				target = _origin_for(p) - Vector2(HAND_W, CARD_H) * 0.5
			var is_bot: bool = p != 0
			var tw := create_tween()
			tw.tween_property(back, "position", target, DEAL_FLIGHT) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			if is_bot:
				# Fade into the avatar instead of blinking out.
				tw.tween_property(back, "modulate:a", 0.0, 0.12)
				tw.tween_callback(back.queue_free)
			# Thin the pile as it empties: step full -> single across the deal.
			dealt += 1
			_deck_apply(DECK_STATES[mini(dealt * DECK_STATES.size() / total, DECK_STATES.size() - 1)])
			await get_tree().create_timer(DEAL_STAGGER).timeout

	if g != _gen:
		return
	await get_tree().create_timer(0.18).timeout
	if g != _gen:
		return
	# Reveal: swap the face-down backs for your real fan, flipping each in.
	for b in your_backs:
		b.queue_free()
	_fade_out_deck()
	_build_hand_from(data.hands[0])
	var i := 0
	for child in _hand.get_children():
		var card := child as Control
		card.pivot_offset = Vector2(HAND_W, CARD_H) * 0.5
		card.scale.x = 0.0
		var tw := create_tween()
		tw.tween_interval(i * 0.03)
		tw.tween_property(card, "scale:x", 1.0, FLIP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1

func _make_back() -> Card:
	var c := CardScene.instantiate() as Card
	c.card_width = int(HAND_W)
	c.face_down = true
	return c

## Global top-left position of each card in your final 10-card fan.
func _hand_slot_positions() -> Array:
	var n := SamLocRules.HAND_SIZE
	var step := HAND_MAX_STEP if n <= 1 else minf(HAND_MAX_STEP, (HAND_AVAIL - HAND_W) / (n - 1))
	var total := HAND_W + step * (n - 1)
	var start := (_vw() - total) * 0.5
	var base := _hand.global_position
	var out: Array = []
	for i in n:
		out.append(base + Vector2(start + i * step, 0.0))
	return out

func _show_deck(centre: Vector2) -> void:
	_hide_deck()
	# Anchor the deck by its bottom edge: the full deck starts centred on `centre`,
	# and thinner state textures keep this bottom line so the top lowers in place.
	var full_h := HAND_W * 1.2 * float(DECK_TEX.get_height()) / float(DECK_TEX.get_width())
	_deck_bottom = centre + Vector2(0.0, full_h * 0.5)
	_deck_shadow = _new_deck_rect(5)
	_deck = _new_deck_rect(6)
	add_child(_deck_shadow)
	add_child(_deck)
	_deck_apply(DECK_TEX)

func _new_deck_rect(z: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.z_index = z
	return r

## Show a deck-stack texture, bottom-anchored, with a card-style drop shadow.
## Call this with deck_stack_1..4 to step the pile thinner as it deals.
func _deck_apply(tex: Texture2D) -> void:
	if _deck == null:
		return
	var dw := HAND_W * 1.2
	var dh := dw * float(tex.get_height()) / float(tex.get_width())
	var size := Vector2(dw, dh)
	var pos := _deck_bottom - Vector2(dw * 0.5, dh)   # bottom-centre anchored
	# Offset tracks WIDTH, so it matches the cards' shadow gap and stays constant
	# as the deck thins between states (height-based would drift).
	var offset := maxf(2.0, roundf(dw * 0.06))
	_deck_shadow.texture = tex
	_deck_shadow.size = size
	_deck_shadow.position = pos + Vector2(0.0, offset)
	_deck_shadow.modulate = Color("180810", 0.55)
	_deck.texture = tex
	_deck.size = size
	_deck.position = pos

func _hide_deck() -> void:
	if is_instance_valid(_deck):
		_deck.queue_free()
	if is_instance_valid(_deck_shadow):
		_deck_shadow.queue_free()
	_deck = null
	_deck_shadow = null

## Soft-remove: same sink-and-fade as the last-played pile so the last card
## doesn't vanish.
func _fade_out_deck() -> void:
	var nodes := [_deck, _deck_shadow]
	_deck = null
	_deck_shadow = null
	for node in nodes:
		if is_instance_valid(node):
			var tw := create_tween()
			tw.set_parallel(true)
			tw.tween_property(node, "position:y", node.position.y + 36.0, 0.28).set_ease(Tween.EASE_IN)
			tw.tween_property(node, "modulate:a", 0.0, 0.28)
			tw.finished.connect(node.queue_free)

func _start_turn(data: GameStateData) -> void:
	for p in _seats:
		_seats[p].active = false
	var seat: Seat = _seats[data.current]
	seat.active = true
	seat.turn_progress = 1.0
	# During a báo sâm deal the banner stays on the declarer's ritual; otherwise
	# it's the usual turn prompt.
	if data.bao_sam != -1:
		_chrome.banner_text = "%s BÁO SÂM" % _seats[data.bao_sam].hero_name
	else:
		_chrome.banner_text = "LƯỢT CỦA BẠN" if data.current == 0 else ""

	if _turn_tween:
		_turn_tween.kill()
	# The ring drains over the same TURN_TIME for every player.
	_turn_tween = create_tween()
	_turn_tween.tween_property(seat, "turn_progress", 0.0, TURN_TIME)

	if data.current == 0:
		_set_my_turn(true)
		var g := _gen
		_turn_tween.finished.connect(func() -> void:
			if g == _gen and _my_turn:
				_on_pass())
	else:
		_set_my_turn(false)
		_schedule_bot(data, data.current)

## Single switch for "it's the player's turn": gates input and greys the buttons.
func _set_my_turn(v: bool) -> void:
	_my_turn = v
	_play_btn.disabled = not v
	_pass_btn.disabled = not v

func _schedule_bot(data: GameStateData, who: int) -> void:
	var g := _gen
	await get_tree().create_timer(randf_range(BOT_DELAY_MIN, BOT_DELAY_MAX)).timeout
	# Ignore if the match moved on while we were waiting.
	if g != _gen or GameState.data != data or data.finished or data.current != who:
		return
	# Reference bot: play its lowest legal combo, otherwise fold.
	var play := SamLocRules.find_play(data, who)
	if play.is_empty():
		GameState.pass_turn(who)
	else:
		GameState.play(who, play)

func _on_played(player: int, cards: Array, data: GameStateData) -> void:
	_set_my_turn(false)
	# Where each card flies from: your real hand positions, else the avatar.
	var origins: Array = []
	if player == 0 and _pending_origins.size() == cards.size():
		origins = _pending_origins
	else:
		var fallback := _origin_for(player)
		for _i in cards.size():
			origins.append(fallback)
	_pending_origins = []
	if player == 0:
		_build_hand_from(data.hands[0])   # collapse the fan to the remaining cards
	_fade_out_pile()                       # ease the previous trick away as the new one arrives
	_fly_to_table(origins, cards, func() -> void:
		_seats[player].card_count = data.hands[player].size()
		last_played = cards
		_rebuild_last_played()
		if not data.finished:
			_start_turn(data))

func _on_passed(_player: int, data: GameStateData) -> void:
	_start_turn(data)

func _on_match_ended(winner: int, deltas: Array, balances: Array, _data: GameStateData) -> void:
	_set_my_turn(false)
	if _turn_tween:
		_turn_tween.kill()
	if _data.bao_sam != -1:
		var ok := not _data.bao_sam_failed
		_chrome.banner_text = "%s BÁO SÂM %s" % [_seats[_data.bao_sam].hero_name, "THẮNG" if ok else "THUA"]
	else:
		_chrome.banner_text = "%s THẮNG" % _seats[winner].hero_name
	for p in _seats:
		var gain: bool = deltas[p] >= 0
		var text := "+%d" % deltas[p] if gain else str(deltas[p])
		_pop_balance(_seats[p], text, POP_GOLD if gain else POP_GREY)
		_seats[p].balance = balances[p]   # tick to the settled amount
	await get_tree().create_timer(WIN_PAUSE).timeout
	GameState.new_match()

## Floating "+30" / "-10" over a seat that rises and fades out.
func _pop_balance(seat: Seat, text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", POP_FONT)
	lbl.add_theme_font_size_override("font_size", 56)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Palette.OUTLINE)
	lbl.add_theme_constant_override("outline_size", 8)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(200.0, 0.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 10
	var center := seat.global_position + Vector2(seat.size.x * 0.5, seat.avatar_size * 0.5)
	lbl.position = center - Vector2(100.0, 36.0)
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 90.0, 1.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.3).set_ease(Tween.EASE_IN)
	tw.finished.connect(lbl.queue_free)

# --- responsive layout ----------------------------------------------------

## Live canvas width. With stretch `expand`, this is 720 on phones but grows
## (toward ~960) on squarer tablets, so everything centres on the REAL width
## instead of the 720 design width.
func _vw() -> float:
	return size.x

## Re-fit the scene to the actual aspect ratio handed to us by `expand`:
##  * the felt + vignette are stretched to cover whatever shape we got,
##  * opponent avatars spread out as the canvas gets wider (tablets),
##  * the player's zone eases downward as the canvas gets taller (thin phones).
## Idempotent — driven off design constants, so it's safe to re-run on resize.
func _relayout() -> void:
	if Engine.is_editor_hint():
		return
	var w := size.x
	var h := size.y

	# Red felt + vignette: fill the real viewport, never leave bare corners.
	($Background as TextureRect).expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	($Vignette as TextureRect).expand_mode = TextureRect.EXPAND_IGNORE_SIZE

	# Opponents: hug the left/right edges and centre the top seat, so a wider
	# canvas pushes the avatars further apart instead of clustering at 720.
	_place_seat(_seats[3], 8.0, 156.0)                                  # left
	_place_seat(_seats[2], w * 0.5 - _seats[2].size.x * 0.5, 88.0)      # top, centred
	_place_seat(_seats[1], w - 8.0 - _seats[1].size.x, 156.0)          # right

	# Extra vertical room (tall phones): ease the player's avatar + hand down a
	# little so the bottom zone isn't stranded high. Buttons stay pinned to the
	# bottom edge. Capped so the hand never collides with the buttons.
	var drop := clampf((h - 1280.0) * 0.15, 0.0, 40.0)
	_seats[0].offset_top = -500.0 + drop
	_seats[0].offset_bottom = -288.0 + drop
	_hand.offset_top = -270.0 + minf(drop, 12.0)
	_hand.offset_bottom = -130.0 + minf(drop, 12.0)

	# Buttons: keep them centred as a pair on the real width.
	var bw := 322.0
	var gap := 20.0
	var start := (w - (bw * 2.0 + gap)) * 0.5
	_pass_btn.offset_left = start
	_pass_btn.offset_right = start + bw
	_play_btn.offset_left = start + bw + gap
	_play_btn.offset_right = start + bw + gap + bw

## Pin a seat to a top-left design coordinate in REAL-canvas space.
func _place_seat(seat: Seat, x: float, y: float) -> void:
	seat.set_anchors_preset(Control.PRESET_TOP_LEFT)
	seat.offset_left = x
	seat.offset_top = y
	seat.offset_right = x + seat.size.x
	seat.offset_bottom = y + seat.size.y

# --- layout ---------------------------------------------------------------

func _build_hand_from(cards_list: Array) -> void:
	for n in _hand.get_children():
		n.free()
	_selected.clear()
	var cards := cards_list.duplicate()
	cards.sort_custom(func(a: Array, b: Array) -> bool: return _rank(a[1]) < _rank(b[1]))
	var n := cards.size()
	if n == 0:
		return
	var step := HAND_MAX_STEP if n <= 1 else minf(HAND_MAX_STEP, (HAND_AVAIL - HAND_W) / (n - 1))
	var total := HAND_W + step * (n - 1)
	var start := (_vw() - total) * 0.5
	for i in n:
		var c := _make_card(cards[i][0], cards[i][1])
		c.position = Vector2(start + i * step, 0.0)
		c.mouse_filter = Control.MOUSE_FILTER_STOP
		c.gui_input.connect(_on_card_input.bind(c))
		_hand.add_child(c)

func _rebuild_last_played() -> void:
	for n in _last_played.get_children():
		n.free()
	var xs := _lp_positions(last_played.size())
	for i in last_played.size():
		var c := _make_card(last_played[i][0], last_played[i][1])
		c.position = Vector2(xs[i], 0.0)
		_last_played.add_child(c)

## Reparent the current table pile off `_last_played` (so the upcoming rebuild
## won't free it) and let it sink + fade out instead of vanishing.
func _fade_out_pile() -> void:
	for c in _last_played.get_children():
		var gp: Vector2 = c.global_position
		_last_played.remove_child(c)
		add_child(c)
		c.position = gp
		c.z_index = 4
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(c, "position:y", gp.y + 36.0, 0.28).set_ease(Tween.EASE_IN)
		tw.tween_property(c, "modulate:a", 0.0, 0.28)
		tw.finished.connect(c.queue_free)

## Local x offsets for `n` overlapping cards on the table, centred on the canvas.
func _lp_positions(n: int) -> Array:
	var xs: Array = []
	if n <= 0:
		return xs
	var step := HAND_W - LP_OVERLAP
	var total := HAND_W + step * (n - 1)
	var start := (_vw() - total) * 0.5
	for i in n:
		xs.append(start + i * step)
	return xs

## Spawn temp cards that fly from each card's own start point (`origins[i]`, a
## global centre) to the table, then run `on_done` once they land.
func _fly_to_table(origins: Array, cards: Array, on_done: Callable) -> void:
	if cards.is_empty():
		on_done.call()
		return
	var xs := _lp_positions(cards.size())
	var lp_origin := _last_played.global_position
	var temps: Array = []
	var last_tw: Tween = null
	for i in cards.size():
		var c := _make_card(cards[i][0], cards[i][1])
		c.z_index = 5
		c.position = origins[i] - Vector2(HAND_W, CARD_H) * 0.5
		add_child(c)
		temps.append(c)
		var target := lp_origin + Vector2(xs[i], 0.0)
		last_tw = create_tween()
		last_tw.tween_property(c, "position", target, FLY_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# All flights share FLY_TIME, so the last tween finishing means all have.
	last_tw.finished.connect(func() -> void:
		for t in temps:
			t.queue_free()
		on_done.call())

## Fallback origin (bots, or if we lost the captured hand positions): the centre
## of the player's avatar.
func _origin_for(player: int) -> Vector2:
	var seat: Seat = _seats[player]
	return seat.global_position + Vector2(seat.size.x * 0.5, seat.avatar_size * 0.5)

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
	if not _my_turn:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var sel: bool = not _selected.get(card, false)
		_selected[card] = sel
		card.position.y = -SELECT_LIFT if sel else 0.0
		card.z_index = 1 if sel else 0

func _on_play() -> void:
	# During the báo sâm window the play button means "declare", not "play".
	if _bao_window:
		_declare_bao_sam()
		return
	if not _my_turn:
		return
	# Capture the cards AND the global centre each sits at, so the flight starts
	# from the actual card position the player picked.
	var cards: Array = []
	_pending_origins = []
	for c in _selected.keys():
		if _selected[c]:
			cards.append([c.row, c.col])
			_pending_origins.append(c.global_position + Vector2(HAND_W, CARD_H) * 0.5)
	if cards.is_empty():
		return
	# Only hand the turn off if the play is legal; a rejected play (wrong number
	# of cards, doesn't beat the table) leaves it your turn to pick again.
	if GameState.play(0, cards):
		_set_my_turn(false)
	else:
		_pending_origins = []

func _on_pass() -> void:
	# During the báo sâm window the pass button means "thôi" (decline the claim).
	if _bao_window:
		_bao_thoi(0)
		_play_btn.disabled = true
		_pass_btn.disabled = true
		return
	if not _my_turn:
		return
	_set_my_turn(false)
	GameState.pass_turn(0)

# --- báo sâm (the pre-game declaration race) ------------------------------

## The "special turn" before play: all four ember timers run at once and anyone
## may claim báo sâm. Bots can't claim, so they just thôi (decline) on their own
## clock — their timer reverts to a normal border. The real game begins when the
## window times out OR all four have thôi'd, unless the human claims first (which
## starts the game immediately, with their lead). Awaitable.
func _bao_sam_window(g: int) -> void:
	_bao_window = true
	_bao_passed = [false, false, false, false]
	_chrome.banner_text = "BÁO SÂM?"
	# Play button = claim, pass button = thôi. (They already read BÁO SÂM / THÔI.)
	_play_btn.disabled = false
	_pass_btn.disabled = false
	# Every seat's timer runs together for the whole window.
	var rings: Array = []
	for p in _seats:
		_seats[p].active = true
		_seats[p].turn_progress = 1.0
		var tw := create_tween()
		tw.tween_property(_seats[p], "turn_progress", 0.0, TURN_TIME)
		rings.append(tw)
	# Bots decide (decline) at staggered moments inside the window.
	for p in [1, 2, 3]:
		_bao_bot_thoi(p, g)
	# Run until claimed, everyone thôi'd, or time's up.
	var elapsed := 0.0
	while _bao_window and elapsed < TURN_TIME and g == _gen:
		if _bao_all_passed():
			break
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	for tw in rings:
		if tw.is_valid():
			tw.kill()
	if g != _gen:
		return
	for p in _seats:
		_seats[p].active = false
	if _bao_window:        # nobody claimed -> fall through to a normal deal
		_close_bao_window()

## A bot waits a beat, then thôis (it can't báo sâm yet).
func _bao_bot_thoi(p: int, g: int) -> void:
	await get_tree().create_timer(randf_range(1.0, TURN_TIME * 0.6)).timeout
	if g != _gen or not _bao_window:
		return
	_bao_thoi(p)

## Mark `p` as having declined: their ember timer reverts to a normal border.
func _bao_thoi(p: int) -> void:
	if _bao_passed.is_empty() or _bao_passed[p]:
		return
	_bao_passed[p] = true
	_seats[p].active = false

func _bao_all_passed() -> bool:
	for v in _bao_passed:
		if not v:
			return false
	return true

## Player claimed báo sâm: declare through the engine, then hand them the lead.
func _declare_bao_sam() -> void:
	_bao_window = false
	GameState.declare_bao_sam(0)
	_restore_action_buttons()

## No claim — fall through to a normal deal.
func _close_bao_window() -> void:
	_bao_window = false
	_restore_action_buttons()

func _restore_action_buttons() -> void:
	_play_btn.text = "ĐÁNH"
	_pass_btn.text = "THÔI"
	_set_my_turn(false)   # _start_turn re-enables them for whoever leads

# --- editor preview (no GameState in the editor) --------------------------

func _editor_preview() -> void:
	var counts := {0: 10, 1: 9, 2: 9, 3: 1}
	var money := {0: 1000, 1: 1230, 2: 970, 3: 1000}
	for p in _seats:
		_seats[p].card_count = counts[p]
		_seats[p].balance = money[p]
		_seats[p].active = false
	_seats[0].active = true
	_seats[0].turn_progress = 0.7
	_build_hand_from([[2, 0], [0, 12], [2, 11], [1, 9], [0, 8], [3, 7], [3, 6], [1, 4], [2, 3], [0, 2]])
	last_played = [[1, 8], [3, 8]]
	_rebuild_last_played()
