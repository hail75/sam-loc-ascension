@tool
extends Control

## Screen A — playable animation-test table: you vs 3 bots.
## Presentation + input plumbing only. All match state lives in the GameState
## autoload (backed by the pure SamLocRules engine); this script just renders
## the state, reports the player's taps, and drives the bot turns on timers so
## the deal / play / win / re-deal animations can be watched.

const CardScene: PackedScene = preload("res://scenes/card/card.tscn")
const DECK_TEX: Texture2D = preload("res://assets/cards/deck_stack.png")
## Dark-fantasy combo splash sheets: a horizontal strip of equal cells, played as a
## cinematic when that combo is dealt. "TỨ QUÝ 2" (quad of deuces) — a golden knight.
const TUQUY2_TEX: Texture2D = preload("res://assets/splash/tuquy2.png")
const TUQUY2_FRAMES := 16
const TUQUY2_CELL := Vector2(127, 127)
## "TỨ QUÝ" — the rising knight shown whenever a quad is PLAYED in-trick (chặt / lead),
## banner-less and quake-less. Distinct from tuquy2 (the ĂN TRẮNG quad-of-deuces).
const TUQUY_TEX: Texture2D = preload("res://assets/splash/tuquy.png")
const TUQUY_FRAMES := 16
const TUQUY_CELL := Vector2(127, 127)
## "SẢNH RỒNG" (ten-card straight) — a winged dragon-knight, cropped on all sides.
const SANHRONG_TEX: Texture2D = preload("res://assets/splash/sanhrong.png")
const SANHRONG_FRAMES := 16
const SANHRONG_CELL := Vector2(200, 200)
## "3 SÁM CÔ" (three triplets) — the jester.
const SAMCO3_TEX: Texture2D = preload("res://assets/splash/3samco.png")
const SAMCO3_FRAMES := 16
const SAMCO3_CELL := Vector2(200, 200)
## "5 ĐÔI" (five pairs) — the hooded assassin.
const NAMDOI_TEX: Texture2D = preload("res://assets/splash/5doi.png")
const NAMDOI_FRAMES := 16
const NAMDOI_CELL := Vector2(147, 147)
## "FULL ĐỎ" / "FULL ĐEN" (ten-card single-colour flush) — the red / black wizard,
## picked by the flush's colour.
const FULLDO_TEX: Texture2D = preload("res://assets/splash/fulldo.png")
const FULLDEN_TEX: Texture2D = preload("res://assets/splash/fullden.png")
const FULL_FRAMES := 16
const FULL_CELL := Vector2(118, 118)
## "CHẶT SÂM" — the skull, shown when an opponent's play breaks a báo sâm. It takes
## the place of the TỨ QUÝ splash if that breaking play is itself a quad.
const CHATSAM_TEX: Texture2D = preload("res://assets/splash/chatsam.png")
const CHATSAM_FRAMES := 16
const CHATSAM_CELL := Vector2(200, 200)
## Deck thinning states, full -> single card, stepped through as it deals.
const DECK_STATES: Array[Texture2D] = [
	preload("res://assets/cards/deck_stack.png"),
	preload("res://assets/cards/deck_stack_1.png"),
	preload("res://assets/cards/deck_stack_2.png"),
	preload("res://assets/cards/deck_stack_3.png"),
	preload("res://assets/cards/deck_stack_4.png"),
]

const BASE_W := 720.0
const HAND_W := 112.0                      # card width in your hand fan
										   # (bigger for readability; the fan
										   # stays in HAND_AVAIL so it just
										   # overlaps a little more)
const CELL_W := 48.0                       # a card cell's source width in cards.png
const CARD_H := HAND_W * 64.0 / CELL_W     # matches the sheet cell aspect
const CARD_PX := HAND_W / CELL_W           # on-screen pixels per source texel for a full card
const HAND_AVAIL := 664.0                  # fan track width
const HAND_MAX_STEP := 66.0
const LP_OVERLAP := 28.0                   # last-played card overlap
const SELECT_LIFT := 28.0
const REVEAL_W := 58                       # card width for the end-of-round opponent reveal
const REVEAL_STEP := 28.0                  # vertical gap between revealed stacked cards
const PILE_FADE := 0.28                     # how long the table pile takes to fade away
const WIN_SETTLE := 0.6                     # let the winning play rest on the table before it fades

const TURN_TIME := 20.0                     # seconds a turn (and the báo sâm window) lasts; the seat ring drains over this for everyone
const BOT_DELAY_MIN := 0.8                  # bots always take a brief "thinking" beat — quick, never instant
const BOT_DELAY_MAX := 1.5
const FLY_TIME := 0.32                      # play-to-centre flight
const AN_TRANG_HOLD := 2.0                    # suspense beat after the deal before the ĂN TRẮNG reveal
const AN_TRANG_FLY := 1.1                    # slow, dramatic ĂN TRẮNG instant-win flight
const AN_TRANG_SMALL := 0.4                  # combo forms small over the seat, grows as it flies
const SPLASH_DIM := 0.78                      # combo-splash dim-overlay opacity
const SPLASH_IN := 2.6                        # splash slide-up + fade in (very slow, dramatic)
const SPLASH_FPS := 4.0                       # combo-splash playback speed (slow)
const SPLASH_OUT := 0.9                       # splash fade out (slow), ends as the anim ends
## Total blocking time of the TỨ QUÝ quad splash (slide-in + one idle pass), so the
## chop pop and the win settle can wait for it before the quad cards land + fly.
const QUAD_SPLASH_TIME := SPLASH_IN + float(TUQUY_FRAMES) / SPLASH_FPS
## Same, for the CHẶT SÂM splash that plays before a báo-sâm-breaking play lands.
const CHATSAM_SPLASH_TIME := SPLASH_IN + float(CHATSAM_FRAMES) / SPLASH_FPS
const SPLASH_SHAKE_TIME := 0.7               # earthquake duration as the splash crashes in
const SPLASH_SHAKE_AMP := 22.0               # earthquake peak offset (decays to 0)
const WIN_PAUSE := 5.0                      # hold on the winner before re-dealing (time to read win/loss + others' cards)
const FEED_PAUSE := 1.2                     # hold on the đền (block-penalty) pops before the normal settle pops
const WIN_FADE := 0.45                      # the reveal cards + amount pops ease out before the next deal
const DEAL_FLIGHT := 0.26                   # one card's deck->seat flight (longer = smoother)
const DEAL_STAGGER := 0.045                 # gap between dealt cards (shorter = faster overall)
const DEAL_FLY_SCALE := 0.75                # dealt cards (and the deck stack) fly/show at 0.75 scale
const FLIP_TIME := 0.16                     # your cards flipping face-up

@onready var _chrome: TableChrome = $Chrome
@onready var _hand: Control = $Hand
@onready var _last_played: Control = $LastPlayedCards
@onready var _play_btn: PixelButton = $PlayButton
@onready var _pass_btn: PixelButton = $PassButton

# The four fixed seat NODES by screen position (you bottom, Grimwald right, Vayne top,
# Seraphine left). `_relayout` always positions these by their fixed spot.
@onready var _seat_you: Seat = $SeatYou
@onready var _seat_grim: Seat = $SeatGrimwald
@onready var _seat_vayne: Seat = $SeatVayne
@onready var _seat_sera: Seat = $SeatSeraphine
# Engine player index -> seat node, rebuilt each deal for the live player count. As bots
# bust the table shrinks: 4p uses all (natural CCW: you, right, top, left); 3p drops the
# TOP (Vayne); 2p also drops the LEFT (Seraphine).
var _seats: Dictionary = {}

## Map the live players (0..n-1) onto seat nodes for `n` players; hide the rest.
func _build_seat_map(n: int) -> void:
	var order: Array
	match n:
		4: order = [_seat_you, _seat_grim, _seat_vayne, _seat_sera]
		3: order = [_seat_you, _seat_grim, _seat_sera]   # top (Vayne) removed
		_: order = [_seat_you, _seat_grim]               # 2: top + left removed
	for nd in [_seat_you, _seat_grim, _seat_vayne, _seat_sera]:
		nd.visible = false
	_seats = {}
	for i in order.size():
		_seats[i] = order[i]
		order[i].visible = true

const POP_FONT: Font = preload("res://assets/fonts/dearpix.ttf")
const NUM_FONT: Font = preload("res://assets/fonts/Pixelta.ttf")  # numerals: the +/- balance pop
const POP_GOLD := Color("f0d68a")     # winner gain
const POP_GREY := Color("9d978d")     # loser loss (muted)

var last_played: Array = []        # cards currently resting on the table
var _revealed: Array = []          # opponents' end-of-round reveal stacks; cleared on next deal
var _pops: Array = []              # floating +/- amount labels; live until the next deal
var _aura_nodes: Array = []        # ĂN TRẮNG resting combo + golden aura; until next deal
var _selected: Dictionary = {}     # Card -> bool
var _my_turn := false
var _restarting := false            # the post-win "tap to restart" overlay is up / dismissing
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
	_play_btn.variant = PixelButton.Variant.GOLD
	_play_btn.font_size = 54
	_pass_btn.text = "THÔI"
	_pass_btn.font_size = 54
	# Player seat label in code too (survives the editor re-saving the .tscn).
	_seat_you.hero_name = "BẠN"
	_build_seat_map(GameState.num_players)   # initial mapping; rebuilt each deal
	_play_btn.pressed.connect(_on_play)
	_pass_btn.pressed.connect(_on_pass)
	GameState.dealt.connect(_on_dealt)
	GameState.played.connect(_on_played)
	GameState.passed.connect(_on_passed)
	GameState.chopped.connect(_on_chopped)
	GameState.match_ended.connect(_on_match_ended)
	GameState.rejected.connect(_on_rejected)
	resized.connect(_relayout)
	_relayout.call_deferred()   # after first layout pass, so seat sizes are valid
	GameState.new_match()

## Vietnamese player-facing copy for each engine rejection reason.
## Only the human's plays get rejected (bots only ever submit legal moves), so a
## rejection while it's your turn means the selected cards weren't a legal play —
## warn softly. (The other warning, "Chọn bài trước khi đánh", fires from _on_play
## when nothing is selected.)
func _on_rejected(_reason: String) -> void:
	if not _my_turn:
		return
	_warn("Bài được chọn không hợp lệ")

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
	# Re-map seats for the live player count (a bot may have busted) and re-fit layout.
	_build_seat_map(data.hands.size())
	_relayout()
	# Reset the table to empty and hide the count badges while we deal.
	last_played = []
	_rebuild_last_played()
	_clear_revealed()   # drop last round's revealed opponent hands
	_clear_pops()       # and the floating +/- amount labels
	_clear_aura()       # and any ĂN TRẮNG combo + aura left on the table
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
	_play_btn.variant = PixelButton.Variant.EMBER   # amber, so it's not mistaken for ĐÁNH
	_pass_btn.text = "THÔI"
	_play_btn.visible = true   # restore if a prior ĂN TRẮNG hid them
	_pass_btn.visible = true
	_set_my_turn(false)
	_chrome.banner_text = "ĐANG CHIA BÀI"

	await _deal_animation(data, g)
	if g != _gen:
		return   # a newer deal superseded this one

	for p in _seats:
		_seats[p].card_count = data.hands[p].size()
		_seats[p].show_badge = true
	# ĂN TRẮNG: someone was dealt an instant-win hand — resolve it now (golden fly-out,
	# banner, payout), skipping the báo sâm window and any normal play.
	if data.an_trang_winner != -1:
		_resolve_an_trang(data, g)
		return
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
	# Your final fan's LOCAL slot x's (same formula _build_hand_from uses). The
	# player's backs are parented to _hand and fly to these local slots, so they
	# land exactly where the face-up fan rebuilds — no matter where _hand sits.
	var hand_n := SamLocRules.HAND_SIZE
	var hand_step := HAND_MAX_STEP if hand_n <= 1 else minf(HAND_MAX_STEP, (HAND_AVAIL - HAND_W) / (hand_n - 1))
	var hand_total := HAND_W + hand_step * (hand_n - 1)
	var hand_start := (_vw() - hand_total) * 0.5
	var your_backs: Array = []
	var hi := 0
	var total := SamLocRules.HAND_SIZE * data.hands.size()
	# Fewer players deal fewer cards, so thin the deck through fewer stack states:
	# 4p = 5, 3p = 4, 2p = 3 (capped at the textures we have).
	var deck_states := mini(data.hands.size() + 1, DECK_STATES.size())
	var dealt := 0

	for _round in SamLocRules.HAND_SIZE:
		for p in data.hands.size():
			if g != _gen:
				return
			var back := _make_back()
			back.z_index = 7
			# Dealt cards fly at 0.75 scale (scaled around their centre).
			back.pivot_offset = Vector2(HAND_W, CARD_H) * 0.5
			back.scale = Vector2.ONE * DEAL_FLY_SCALE
			var target: Vector2
			if p == 0:
				# Parent to _hand and aim at the LOCAL slot, so the back lands at the
				# same level the face-up fan rebuilds to.
				_hand.add_child(back)
				back.position = deck_tl - _hand.global_position
				target = Vector2(hand_start + hi * hand_step, 0.0)
				hi += 1
				your_backs.append(back)
			else:
				add_child(back)
				back.position = deck_tl
				target = _origin_for(p) - Vector2(HAND_W, CARD_H) * 0.5
			var is_bot: bool = p != 0
			var tw := create_tween()
			tw.tween_property(back, "position", target, DEAL_FLIGHT) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			if is_bot:
				# Bots' cards stay at 0.75 and fade into the avatar.
				tw.tween_property(back, "modulate:a", 0.0, 0.12)
				tw.tween_callback(back.queue_free)
			else:
				# Your card grows from 0.75 up to full size, landing in the hand at
				# 112 — the scale-up runs over the back half of the flight.
				tw.parallel().tween_property(back, "scale", Vector2.ONE, DEAL_FLIGHT * 0.5) \
					.set_delay(DEAL_FLIGHT * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			# Thin the pile as it empties: step full -> single across the deal.
			dealt += 1
			_deck_apply(DECK_STATES[mini(dealt * deck_states / total, deck_states - 1)])
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

func _show_deck(centre: Vector2) -> void:
	_hide_deck()
	# Anchor the deck by its bottom edge: the full deck starts centred on `centre`,
	# and thinner state textures keep this bottom line so the top lowers in place.
	var full_h := float(DECK_TEX.get_height()) * CARD_PX * DEAL_FLY_SCALE
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
	# Render the deck at the SAME pixels-per-texel as a 0.75-scale card. The deck
	# art is 49px wide vs a card's 48px, so we size by its OWN texture pixels — not
	# by card width — or the two wouldn't share a scale.
	var px := CARD_PX * DEAL_FLY_SCALE
	var dw := float(tex.get_width()) * px
	var dh := float(tex.get_height()) * px
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
		# Đền obligation: the player to your left holds ONE card — you can't pass, you
		# must play (and should play your highest). Grey out THÔI. (Timeout auto-plays.)
		var forced := _den_obligation(data)
		if forced:
			_pass_btn.disabled = true
		var g := _gen
		_turn_tween.finished.connect(func() -> void:
			if g != _gen or not _my_turn:
				return
			if forced:
				var pl := SamLocRules.find_play(GameState.data, 0)
				if pl.is_empty():
					_on_pass()
				else:
					GameState.play(0, pl)
					_set_my_turn(false)
			else:
				_on_pass())
	else:
		_set_my_turn(false)
		_schedule_bot(data, data.current)

## True when it's your turn and the player who ACTS NEXT (the next active seat, after
## any folds) holds exactly one card in a single context (you're leading, or answering
## a single you CAN beat) — so you're obliged to play (no passing). Greys out THÔI.
func _den_obligation(data: GameStateData) -> bool:
	if data.current != 0 or data.bao_sam != -1:
		return false
	if data.hands[SamLocRules._next_active(data, 0)].size() != 1:
		return false
	if data.table.is_empty():
		return true
	if SamLocRules.classify(data.table).type != SamLocRules.Combo.SINGLE:
		return false
	for c in data.hands[0]:
		if SamLocRules.beats(data.table, [c]):
			return true
	return false

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
	var on_landed := func() -> void:
		_seats[player].card_count = data.hands[player].size()
		last_played = cards
		_rebuild_last_played()
		if not data.finished:
			_start_turn(data)
	# A play that breaks a báo sâm gets the CHẶT SÂM skull (titled, with the quake).
	# Otherwise a quad (tứ quý / chặt) gets the rising-knight splash — the SAME
	# animation as ĂN TRẮNG's TỨ QUÝ, but with NO title banner and NO screen quake.
	# Either plays first, then the cards fly to the table as usual.
	if _breaks_bao_sam(player, data):
		await _play_combo_splash("CHẶT SÂM", CHATSAM_TEX, CHATSAM_FRAMES, CHATSAM_CELL, _gen)
	elif _is_quad(cards):
		await _play_combo_splash("", TUQUY_TEX, TUQUY_FRAMES, TUQUY_CELL, _gen, false, false)
	_fly_to_table(origins, cards, on_landed)

func _on_passed(_player: int, data: GameStateData) -> void:
	# A pass that ENDS the trick clears the table (engine ran _new_trick): the next
	# player opens a fresh hand. Fade the last-played pile away now — the same sink-
	# and-fade we do before the next card lands — so it reads as "new hand, you don't
	# have to follow this", instead of leaving the dead trick sitting on the felt.
	if data.table.is_empty() and not data.finished:
		_fade_out_pile()
	_start_turn(data)

func _on_match_ended(winner: int, deltas: Array, feed: Array, balances: Array, _data: GameStateData) -> void:
	_set_my_turn(false)
	# The match is over: freeze every countdown. Bump the generation so any stale
	# bot/timeout await bails, kill the ring tween, and clear `active` on all seats
	# so no turn ring keeps draining and no avatar keeps bobbing.
	_gen += 1
	if _turn_tween:
		_turn_tween.kill()
	for p in _seats:
		_seats[p].active = false
	if _data.bao_sam != -1:
		var ok := not _data.bao_sam_failed
		_chrome.banner_text = "BÁO SÂM THÀNH CÔNG" if ok else "BÁO SÂM THẤT BẠI"
	elif _data.foul_finish != -1:
		# Thối 2: no winner — the fouler forfeited by ending on a deuce.
		_chrome.banner_text = "%s THỐI" % _seats[_data.foul_finish].hero_name
	else:
		_chrome.banner_text = "%s THẮNG" % _seats[winner].hero_name
	# The winning play is still FLYING to the table when match_ended fires (see
	# _on_played: the cards only land + register as `last_played` after FLY_TIME).
	# Wait for them to land and rest a beat so the final play reads, THEN fade the
	# whole pile away and — once it's gone — bring up the reveal and the +/- pops
	# together as one beat.
	# A quad finisher (or a báo-sâm breaker) plays its splash before the cards fly,
	# so wait it out.
	var land_time := _pre_fly_time(_data.table_owner, _data.table, _data) + FLY_TIME
	await get_tree().create_timer(land_time + WIN_SETTLE).timeout
	_fade_out_pile()
	await get_tree().create_timer(PILE_FADE).timeout
	_reveal_opponent_hands(_data)     # show what the others were holding
	# Đền (block-penalty) first, as its own beat: a transient +/- over each affected
	# seat, money ticked to the post-feed / pre-pot balance.
	var has_feed := false
	for v in feed:
		if v != 0:
			has_feed = true
			break
	if has_feed:
		for p in _seats:
			if feed[p] == 0:
				continue
			var fg: bool = feed[p] > 0
			var ftext := "+%d" % feed[p] if fg else str(feed[p])
			_pop_chop(_seats[p], ftext, POP_GOLD if fg else POP_GREY)
			# Caption the payer: "THỐI" if they fouled (ended on a 2), else the đền offender.
			if not fg:
				var why := "THỐI" if p == _data.foul_finish else "ĐỀN"
				_pop_reason(_seats[p], [why], false)
			_seats[p].balance = balances[p] - deltas[p]   # after the feed, before the pot
		await get_tree().create_timer(FEED_PAUSE).timeout
	# Then the winner-takes-all settle pops — skipped entirely on a foul (no pot moved).
	var has_delta := false
	for v in deltas:
		if v != 0:
			has_delta = true
			break
	if has_delta:
		for p in _seats:
			var gain: bool = deltas[p] >= 0
			var text := "+%d" % deltas[p] if gain else str(deltas[p])
			_pop_balance(_seats[p], text, POP_GOLD if gain else POP_GREY, gain)
			# Caption WHY a loser owes extra (CÓNG / THỐI), beside the −amount. Skipped on
			# báo sâm (fixed scoring, no card penalty) and for the winner.
			if not gain and _data.bao_sam == -1:
				_pop_reason(_seats[p], SamLocRules.loss_reasons(_data.hands[p]), true)
			# Báo sâm declarer who fouled on a 2 still gets the "THỐI" caption.
			elif p == _data.foul_finish:
				_pop_reason(_seats[p], ["THỐI"], true)
			_seats[p].balance = balances[p]   # tick to the settled amount
	await get_tree().create_timer(WIN_PAUSE).timeout
	await _fade_out_win()   # ease the reveal cards + pops away
	_show_restart_prompt()  # then dim the screen and wait for a tap to re-deal

## ĂN TRẮNG (instant win on the deal): every qualifying combo flies to the table in a
## golden aura, weakest tier first, strongest last. Then the banner names the winner
## and the +/- payout pops (each loser pays 20 stake + their own 2/quad penalty).
func _resolve_an_trang(data: GameStateData, g: int) -> void:
	if _turn_tween:
		_turn_tween.kill()
	for p in _seats:
		_seats[p].active = false
	# The confusing beat: input is gated off (taps do nothing). If YOU don't have the
	# instant-win, both buttons flip to "CHẠY" (run!) — live-looking but inert, max
	# confusion. If you ARE a holder, hide the buttons entirely (you've nothing to do).
	_my_turn = false
	_chrome.banner_text = ""
	var you_an_trang := SamLocRules.an_trang_tier(data.hands[0]) != SamLocRules.AnTrang.NONE
	if you_an_trang:
		_play_btn.visible = false
		_pass_btn.visible = false
	else:
		_play_btn.text = "CHẠY"
		_pass_btn.text = "CHẠY"
		_play_btn.disabled = false
		_pass_btn.disabled = false
	await get_tree().create_timer(AN_TRANG_HOLD).timeout
	if g != _gen:
		return
	# Reveal: hide the controls for the rest of the instant-win sequence.
	_play_btn.visible = false
	_pass_btn.visible = false
	var plays := SamLocRules.an_trang_plays(data)
	var winner: int = plays.back()["player"]
	# Dark-fantasy combo splash for the winning combo (every tier has its own art).
	var sp := _an_trang_splash(int(plays.back()["tier"]), data.hands[winner])
	if not sp.is_empty():
		await _play_combo_splash(sp["title"], sp["tex"], sp["frames"], sp["cell"], g)
		if g != _gen:
			return
	# Fly each combo in (only the combo cards — e.g. the four 2s, the triplet cards —
	# not the whole hand), fading the previous one as the next (stronger) arrives.
	for play in plays:
		if g != _gen:
			return
		var combo := SamLocRules.an_trang_cards(data.hands[play["player"]], play["tier"])
		# If the human is the one flying, drop the combo cards from their visible fan.
		if play["player"] == 0:
			var keep: Array = []
			for c in data.hands[0]:
				if not _card_in(combo, c):
					keep.append(c)
			_build_hand_from(keep)
		_fade_aura()
		_aura_nodes = await _an_trang_fly(play["player"], combo, g)
		if g != _gen:
			return
	_chrome.banner_text = "%s ĂN TRẮNG" % _seats[winner].hero_name
	# Settle the deferred payout and pop the flat +/- amounts (20 stake each, like báo sâm).
	var res := GameState.commit_an_trang()
	var deltas: Array = res["deltas"]
	var balances: Array = res["balances"]
	for p in _seats:
		var gain: bool = deltas[p] >= 0
		var text := "+%d" % deltas[p] if gain else str(deltas[p])
		_pop_balance(_seats[p], text, POP_GOLD if gain else POP_GREY, gain)
		_seats[p].balance = balances[p]
	await get_tree().create_timer(WIN_PAUSE).timeout
	if g != _gen:
		return
	await _fade_out_win()
	_show_restart_prompt()

## Fly one player's whole hand to the table, wrapped in a golden aura, slowly. Returns
## the resting nodes (cards + aura) so the caller can fade them when the next combo
## arrives or the round ends.
func _an_trang_fly(player: int, cards: Array, g: int) -> Array:
	var origin := _origin_for(player)
	var n := cards.size()
	var step := HAND_MAX_STEP if n <= 1 else minf(HAND_MAX_STEP, (HAND_AVAIL - HAND_W) / float(n - 1))
	var total := HAND_W + step * (n - 1)
	var startx := (_vw() - total) * 0.5
	var ty := _last_played.global_position.y
	# Aura + fan are ONE rigid group so they stay glued together — the whole group
	# flies as a unit (no separate aura drifting at its own speed).
	var fan_half := Vector2(total, CARD_H) * 0.5
	var group := Control.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.z_index = 5
	group.pivot_offset = fan_half           # scale/breathe around the fan centre
	add_child(group)
	var aura := _make_aura(Vector2(total, CARD_H))   # behind the cards
	aura.z_index = 0
	aura.modulate.a = 0.0
	group.add_child(aura)
	for i in n:
		var c := _make_card(cards[i][0], cards[i][1])
		c.shadow = false                            # the aura is the glow; no drop shadow
		c.position = Vector2(i * step, 0.0)
		c.z_index = 1                               # keep the fan in front of the aura glow
		group.add_child(c)
	# Form the combo SMALL, centred over the player's seat (stays on-screen for side
	# seats); it grows to full size as it flies, keeping centre on `origin`.
	group.scale = Vector2.ONE * AN_TRANG_SMALL
	group.position = origin - fan_half
	# Glow the aura in and breathe it (bound to the aura, so freeing kills the loop).
	create_tween().tween_property(aura, "modulate:a", 1.0, 0.3)
	var pulse := aura.create_tween().set_loops()
	pulse.tween_property(aura, "scale", Vector2.ONE * 1.025, 1.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(aura, "scale", Vector2.ONE, 1.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Fly the whole group straight to the table (no sit).
	var fly := create_tween()
	fly.set_parallel(true)
	fly.tween_property(group, "position", Vector2(startx, ty), AN_TRANG_FLY) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	fly.tween_property(group, "scale", Vector2.ONE, AN_TRANG_FLY) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await fly.finished
	if g != _gen:
		group.queue_free()
		return []
	return [group]

## The avatar's soft glow, supercharged: a StyleBoxFlat with an invisible box and a
## big, bright blurred shadow (the active avatar uses ember alpha 0.12–0.32, size
## 8–14; this is gold, alpha ~0.9, size ~48). `rect` is the card-fan footprint it hugs.
func _make_aura(rect: Vector2) -> Panel:
	var sb := StyleBoxFlat.new()
	sb.anti_aliasing = false
	sb.bg_color = Color(Palette.GOLD_HI, 0.0)        # invisible box; only the glow shows
	sb.set_corner_radius_all(20)
	sb.shadow_color = Color(Palette.GOLD_HI, 0.95)   # strong, concentrated
	sb.shadow_size = 20                              # tighter halo (48 read too wide/diluted)
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", sb)
	p.size = rect
	p.pivot_offset = rect * 0.5
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.z_index = 4
	return p

## Fade out the currently-resting ĂN TRẮNG combo + aura (when a stronger one lands).
func _fade_aura() -> void:
	var nodes := _aura_nodes
	_aura_nodes = []
	for node in nodes:
		if is_instance_valid(node):
			var tw := create_tween()
			tw.tween_property(node, "modulate:a", 0.0, PILE_FADE)
			tw.finished.connect(node.queue_free)

## Drop the ĂN TRẮNG combo + aura immediately (called on the next deal).
func _clear_aura() -> void:
	for node in _aura_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_aura_nodes.clear()

## A rounded box in a palette color, AA off so the corners stay pixel-crisp.
func _round_panel(color: Color, radius: int) -> Panel:
	var sb := StyleBoxFlat.new()
	sb.anti_aliasing = false
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## The combo title in a FULL-WIDTH framed banner — palette frame style (dark OUTLINE
## rim, GOLD trim, dark FRAME fill, nested like the table chrome). The title is drawn
## (not a Label) so it's centred the same way as the rest of the game: gold fill, a
## thin dark outline, and a drop shadow.
const COMBO_BANNER_H := 128.0
func _make_combo_banner(text: String) -> Control:
	var bw := _vw()
	var bh := COMBO_BANNER_H
	var over := 60.0   # overhang so the rounded LEFT/RIGHT edges fall off-screen — only
					   # the top/bottom borders show, making it a wide edge-to-edge band
	var root := Control.new()
	root.size = Vector2(bw, bh)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outer := _round_panel(Palette.OUTLINE, 14)        # dark top/bottom rim
	outer.position = Vector2(-over, 0.0)
	outer.size = Vector2(bw + over * 2.0, bh)
	root.add_child(outer)
	var trim := _round_panel(Palette.GOLD, 10)            # gold band
	trim.position = Vector2(-over, 6.0)
	trim.size = Vector2(bw + over * 2.0, bh - 12.0)
	root.add_child(trim)
	var fill := _round_panel(Palette.FRAME, 8)            # dark fill
	fill.position = Vector2(-over, 11.0)
	fill.size = Vector2(bw + over * 2.0, bh - 22.0)
	root.add_child(fill)
	# Title drawn (not a Label) so it's dead-centred in the full width.
	var title := _ComboTitle.new()
	title.text = text
	title.size = Vector2(bw, bh)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)
	return root

## Tiny draw-only Control: the combo title, optically centred like PixelDraw, with a
## drop shadow, a thin dark outline, and a gold fill.
class _ComboTitle extends Control:
	const FONT: Font = preload("res://assets/fonts/dearpix.ttf")
	const FSIZE := 96
	var text := "":
		set(v):
			text = v
			queue_redraw()
	## A nudge so the visible caps land dead-centre (DearPix sits a touch high/left).
	const NUDGE := Vector2(4.0, 0.0)
	func _draw() -> void:
		var ts := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FSIZE)
		# Horizontal: centre the advance width. Vertical: baseline at centre + half the
		# ascent, which optically centres the cap/diacritic cluster (no descenders here).
		var base := Vector2((size.x - ts.x) * 0.5, size.y * 0.5 + FONT.get_ascent(FSIZE) * 0.5) + NUDGE
		# drop shadow, then a thin dark outline (8 directions), then the gold fill.
		draw_string(FONT, base + Vector2(4.0, 6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FSIZE, Color(Palette.OUTLINE, 0.85))
		for d in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3), Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(2, 2)]:
			draw_string(FONT, base + d, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FSIZE, Palette.OUTLINE)
		draw_string(FONT, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FSIZE, Palette.GOLD_HI)

## A cinematic combo reveal: dim the screen, slide a full-width character splash UP
## from the bottom + fade it in, with the combo title banner over its top edge. Only
## once it has fully faded in does the knight start his frames. Then it all fades out.
## `sheet` is a horizontal strip of `frames` cells of `cell` size. Awaitable; bails if stale.
func _play_combo_splash(title: String, sheet: Texture2D, frames: int, cell: Vector2, g: int,
		do_quake: bool = true, show_banner: bool = true) -> void:
	var scl := _vw() / cell.x                       # fit the cropped art to full width
	# Overlay holds the dim + art, screen-fixed via counter-shake so only the TABLE
	# (the other children of self) quakes underneath it.
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 60
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	# Knight (full width), bottom-aligned so the cropped feet sit on the screen edge.
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(0.0, 0.0, cell.x, cell.y)
	var knight := TextureRect.new()
	knight.texture = atlas
	knight.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	knight.size = cell
	knight.pivot_offset = cell * 0.5
	knight.scale = Vector2(scl, scl)
	knight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var knight_y := size.y - cell.y * 0.5 * (1.0 + scl)   # rests with its bottom on the edge
	knight.position = Vector2(_vw() * 0.5 - cell.x * 0.5, knight_y)
	knight.modulate.a = 0.0
	overlay.add_child(knight)
	# Combo title in a palette-framed banner, placed over the art's TOP edge so it hides
	# the cropped upper edge of the character.
	var knight_top := size.y - cell.y * scl
	var banner: Control = null
	var banner_y := 0.0
	if show_banner:
		banner = _make_combo_banner(title)
		banner_y = knight_top - banner.size.y + 8.0   # bottom sits snug on the gif's top edge
		banner.position = Vector2(0.0, banner_y)
		banner.modulate.a = 0.0
		overlay.add_child(banner)
	# Earthquake: shake the TABLE (self) and counter it on the overlay so the dim + art
	# stay put. Decays over SPLASH_SHAKE_TIME, runs alongside the slow slide-in.
	if do_quake:
		var quake := create_tween()
		var qstep := 0.035
		var qn := int(SPLASH_SHAKE_TIME / qstep)
		for i in qn:
			var amp := SPLASH_SHAKE_AMP * (1.0 - float(i) / float(qn))
			quake.tween_callback(func() -> void:
				var o := Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
				position = o
				if is_instance_valid(overlay):
					overlay.position = -o)
			quake.tween_interval(qstep)
		quake.tween_callback(func() -> void:
			position = Vector2.ZERO
			if is_instance_valid(overlay):
				overlay.position = Vector2.ZERO)
	# Slide UP from below + fade in (slow). Knight + title rise together.
	var slide := 320.0
	var t_in := create_tween()
	t_in.set_parallel(true)
	t_in.tween_property(dim, "color:a", SPLASH_DIM, SPLASH_IN * 0.55)
	t_in.tween_property(knight, "modulate:a", 1.0, SPLASH_IN)
	t_in.tween_property(knight, "position:y", knight_y, SPLASH_IN) \
		.from(knight_y + slide).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if banner != null:
		t_in.tween_property(banner, "modulate:a", 1.0, SPLASH_IN)
		t_in.tween_property(banner, "position:y", banner_y, SPLASH_IN) \
			.from(banner_y + slide).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t_in.finished
	if g != _gen:
		overlay.queue_free()
		return
	# Only NOW (fully faded in) start the knight's idle loop (bound to the node).
	var step := func(fr: float) -> void:
		var f := int(fr) % frames
		atlas.region = Rect2(float(f) * cell.x, 0.0, cell.x, cell.y)
	# Play the idle through ONCE at SPLASH_FPS; the slow fade-out finishes exactly as
	# the animation reaches its last frame.
	var anim_dur := float(frames) / SPLASH_FPS
	knight.create_tween().tween_method(step, 0.0, float(frames), anim_dur)
	await get_tree().create_timer(maxf(0.0, anim_dur - SPLASH_OUT)).timeout
	if g != _gen:
		overlay.queue_free()
		return
	var t_out := create_tween()
	t_out.tween_property(overlay, "modulate:a", 0.0, SPLASH_OUT)
	await t_out.finished
	overlay.queue_free()

## A chặt (chop) just landed: pop a transient +amount / -amount over the chopper
## and the chopped seat (synced to the bombing cards landing) and tick both seats'
## money to the new balances.
func _on_chopped(from_player: int, to_player: int, amount: int, bals: Array) -> void:
	var g := _gen
	# Wait for the chopping cards to reach the table so the +/- reads as the payout.
	# A single-quad chop plays the TỨ QUÝ (or CHẶT SÂM) splash before the cards fly; a
	# double-quad (8 cards) flies normally unless it breaks a báo sâm.
	var gd := GameState.data
	var land_time := _pre_fly_time(gd.table_owner, gd.table, gd) + FLY_TIME
	await get_tree().create_timer(land_time).timeout
	if g != _gen:
		return
	_pop_chop(_seats[from_player], str(-amount), POP_GREY)
	_pop_chop(_seats[to_player], "+%d" % amount, POP_GOLD)
	_seats[from_player].balance = bals[from_player]
	_seats[to_player].balance = bals[to_player]

## End-of-match "+340" / "-110" over a seat: punches in and STAYS put for the whole
## win moment (cleared on the next deal). Winner's gain is bigger and pops harder.
func _pop_balance(seat: Seat, text: String, color: Color, gain: bool) -> void:
	_pop_amount(seat, text, color, 76 if gain else 56, 10 if gain else 8,
		1.18 if gain else 1.0, true)

## Mid-game chặt amount: same punch, but transient — it holds a beat, floats up and
## fades away (it is NOT tracked with the sticky end-of-match pops).
func _pop_chop(seat: Seat, text: String, color: Color) -> void:
	_pop_amount(seat, text, color, 56, 8, 1.12, false)

## Floating amount label over a seat. `sticky` pops stay until the next deal (the
## win settle); non-sticky pops punch in, hold, then drift up and fade out.
func _pop_amount(seat: Seat, text: String, color: Color, fsize: int, osize: int,
		over: float, sticky: bool) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", NUM_FONT)
	lbl.add_theme_font_size_override("font_size", fsize)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Palette.OUTLINE)
	lbl.add_theme_constant_override("outline_size", osize)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(240.0, 0.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 10
	# Scale around the label's centre so the punch grows from the middle.
	lbl.pivot_offset = Vector2(120.0, 32.0)
	var center := seat.global_position + Vector2(seat.size.x * 0.5, seat.avatar_size * 0.5)
	lbl.position = center - Vector2(120.0, 36.0)
	lbl.scale = Vector2(0.2, 0.2)
	add_child(lbl)

	var tw := create_tween()
	# Punch in: snap up past full size with a springy back-ease, then settle.
	tw.tween_property(lbl, "scale", Vector2.ONE * over, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if sticky:
		# Stays put for the whole win moment; removed on the next deal, so it lives
		# exactly as long as the revealed opponent hands.
		_pops.append(lbl)
	else:
		# Transient: hold a beat, then float up and fade out before freeing.
		tw.tween_interval(0.7)
		tw.tween_property(lbl, "position:y", lbl.position.y - 48.0, 0.4).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(lbl.queue_free)

## Penalty caption(s) in DearPix — CÓNG / THỐI / ĐỀN — stacked just under a seat's
## −amount, same muted grey as the loss, so the player reads WHY they paid extra.
## `sticky` matches the amount it annotates (settle pops stay; the đền pop is transient).
func _pop_reason(seat: Seat, lines: Array, sticky: bool) -> void:
	if lines.is_empty():
		return
	var center := seat.global_position + Vector2(seat.size.x * 0.5, seat.avatar_size * 0.5)
	for i in lines.size():
		var lbl := Label.new()
		lbl.text = lines[i]
		lbl.add_theme_font_override("font", POP_FONT)            # DearPix
		lbl.add_theme_font_size_override("font_size", 28)
		lbl.add_theme_color_override("font_color", POP_GREY)     # same grey as the "−"
		lbl.add_theme_color_override("font_outline_color", Palette.OUTLINE)
		lbl.add_theme_constant_override("outline_size", 6)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.custom_minimum_size = Vector2(240.0, 0.0)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.z_index = 10
		lbl.pivot_offset = Vector2(120.0, 16.0)
		var y := center.y + 30.0 + float(i) * 32.0
		lbl.position = Vector2(center.x - 120.0, y)
		lbl.scale = Vector2(0.2, 0.2)
		add_child(lbl)
		var tw := create_tween()
		tw.tween_property(lbl, "scale", Vector2.ONE * 1.1, 0.28) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(lbl, "scale", Vector2.ONE, 0.16) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if sticky:
			_pops.append(lbl)
		else:
			tw.tween_interval(0.7)
			tw.tween_property(lbl, "position:y", y - 48.0, 0.4).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_IN)
			tw.chain().tween_callback(lbl.queue_free)

## Ease the win moment away: fade the revealed opponent hands and the +/- amount
## pops out together, then free them, just before the next deal arrives.
func _fade_out_win() -> void:
	var nodes: Array = []
	nodes.append_array(_revealed)
	nodes.append_array(_pops)
	nodes.append_array(_aura_nodes)
	_revealed.clear()
	_pops.clear()
	_aura_nodes.clear()
	for n in nodes:
		if is_instance_valid(n):
			var tw := create_tween()
			tw.tween_property(n, "modulate:a", 0.0, WIN_FADE).set_ease(Tween.EASE_IN)
			tw.finished.connect(n.queue_free)
	await get_tree().create_timer(WIN_FADE).timeout

## Drop the floating +/- amount labels (called on the next deal).
func _clear_pops() -> void:
	for lbl in _pops:
		if is_instance_valid(lbl):
			lbl.queue_free()
	_pops.clear()

## After the win moment has faded, dim the whole screen and invite a tap to deal
## again — the match no longer re-deals on its own. The dim overlay swallows the
## tap, so nothing underneath reacts.
func _show_restart_prompt() -> void:
	_restarting = false
	var dim := ColorRect.new()
	dim.name = "RestartDim"
	dim.color = Color(Palette.OUTLINE, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.z_index = 50
	dim.modulate.a = 0.0
	add_child(dim)
	var lbl := Label.new()
	lbl.text = "Chạm để bắt đầu lại"
	lbl.add_theme_font_override("font", POP_FONT)
	lbl.add_theme_font_size_override("font_size", 46)
	lbl.add_theme_color_override("font_color", Palette.GOLD_HI)
	lbl.add_theme_color_override("font_outline_color", Palette.OUTLINE)
	lbl.add_theme_constant_override("outline_size", 8)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(lbl)
	create_tween().tween_property(dim, "modulate:a", 1.0, WIN_FADE)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
				and event.pressed:
			_on_restart_tap(dim))

## Tap on the dim overlay: fade it out, then deal the next match.
func _on_restart_tap(dim: ColorRect) -> void:
	if _restarting:
		return
	_restarting = true
	var tw := create_tween()
	tw.tween_property(dim, "modulate:a", 0.0, 0.3).set_ease(Tween.EASE_IN)
	tw.finished.connect(func() -> void:
		dim.queue_free()
		GameState.new_match())

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

	# Push the top row below the device's safe area so a punch-hole / notch camera
	# can't clip the top seat's border. `safe` is in screen pixels, so convert to
	# canvas units by the active stretch scale (height px -> design units).
	# Only modern (taller-than-16:9) phones get a top inset; old 16:9 phones stay
	# exactly as before. With `expand`, `h / w` IS the device aspect, so this is a
	# reliable "is this a notch-era phone?" test. We gate the safe-area read behind
	# it on purpose: get_display_safe_area() also excludes the STATUS BAR, so on a
	# 16:9 phone it would report a non-zero top and wrongly push the row down.
	var top_inset := 0.0
	const OLD_ASPECT := 16.0 / 9.0
	if w > 0.0 and (h / w) > OLD_ASPECT + 0.02:
		# Baseline gap for the camera; let the real cutout win if it's bigger.
		top_inset = 56.0
		var win := DisplayServer.window_get_size()
		if win.y > 0:
			var safe := DisplayServer.get_display_safe_area()
			top_inset = maxf(top_inset, clampf(float(safe.position.y) * (h / float(win.y)), 0.0, 120.0))

	# Drop the menu glyph by the same amount so it clears the camera too.
	_chrome.top_inset = top_inset

	# Opponents pinned to their FIXED screen spots (hidden ones are positioned anyway,
	# harmlessly): Seraphine left, Vayne top-centre, Grimwald right.
	_place_seat(_seat_sera, 8.0, 156.0 + top_inset)                          # left
	_place_seat(_seat_vayne, w * 0.5 - _seat_vayne.size.x * 0.5, 88.0 + top_inset)  # top, centred
	_place_seat(_seat_grim, w - 8.0 - _seat_grim.size.x, 156.0 + top_inset)  # right

	# Tall phones (aspect > 16:9): only the three opponent avatars drop (via
	# top_inset above) to clear the camera. The player's own avatar + hand stay
	# pinned to the bottom — they're bottom-anchored, so they never move.
	_seat_you.offset_top = -500.0
	_seat_you.offset_bottom = -288.0
	_hand.offset_top = -305.0
	_hand.offset_bottom = -165.0

	# Buttons: keep them centred as a pair on the real width.
	var bw := 322.0
	var gap := 20.0
	var start := (w - (bw * 2.0 + gap)) * 0.5
	_pass_btn.offset_left = start
	_pass_btn.offset_right = start + bw
	_play_btn.offset_left = start + bw + gap
	_play_btn.offset_right = start + bw + gap + bw
	# Nudge the button pair up a touch off the very bottom edge (set from code so
	# it survives the editor re-saving the .tscn).
	for btn in [_pass_btn, _play_btn]:
		btn.offset_top = -118.0
		btn.offset_bottom = -20.0

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
		tw.tween_property(c, "position:y", gp.y + 36.0, PILE_FADE).set_ease(Tween.EASE_IN)
		tw.tween_property(c, "modulate:a", 0.0, PILE_FADE)
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

## Four cards of one rank — a quad (tứ quý), which gets the build-up flight.
## The ĂN TRẮNG splash for `tier` as { title, tex, frames, cell }, or {} if none.
## The flush picks the red or black wizard from the winning hand's colour.
func _an_trang_splash(tier: int, hand: Array) -> Dictionary:
	match tier:
		SamLocRules.AnTrang.THREE_TRIPLES:
			return {"title": "3 SÁM CÔ", "tex": SAMCO3_TEX, "frames": SAMCO3_FRAMES, "cell": SAMCO3_CELL}
		SamLocRules.AnTrang.TEN_STRAIGHT:
			return {"title": "SẢNH RỒNG", "tex": SANHRONG_TEX, "frames": SANHRONG_FRAMES, "cell": SANHRONG_CELL}
		SamLocRules.AnTrang.FIVE_PAIRS:
			return {"title": "5 ĐÔI", "tex": NAMDOI_TEX, "frames": NAMDOI_FRAMES, "cell": NAMDOI_CELL}
		SamLocRules.AnTrang.FLUSH:
			var red := SamLocRules.card_color(hand[0]) == 0
			return {"title": "FULL ĐỎ" if red else "FULL ĐEN",
				"tex": FULLDO_TEX if red else FULLDEN_TEX, "frames": FULL_FRAMES, "cell": FULL_CELL}
		SamLocRules.AnTrang.QUAD_TWOS:
			return {"title": "TỨ QUÝ 2", "tex": TUQUY2_TEX, "frames": TUQUY2_FRAMES, "cell": TUQUY2_CELL}
	return {}

## True when `player`'s play (already applied in `data`) is the one that broke a
## báo sâm — any opponent of the declarer landing a card ends the declaration.
func _breaks_bao_sam(player: int, data: GameStateData) -> bool:
	return data.bao_sam != -1 and player != data.bao_sam and data.bao_sam_failed

## How long `_on_played` holds a play's cards back for its splash before they fly.
func _pre_fly_time(player: int, cards: Array, data: GameStateData) -> float:
	if cards.is_empty():
		return 0.0
	if _breaks_bao_sam(player, data):
		return CHATSAM_SPLASH_TIME
	if _is_quad(cards):
		return QUAD_SPLASH_TIME
	return 0.0

func _is_quad(cards: Array) -> bool:
	if cards.size() != 4:
		return false
	for c in cards:
		if c[1] != cards[0][1]:
			return false
	return true

## Fallback origin (bots, or if we lost the captured hand positions): the centre
## of the player's avatar.
func _origin_for(player: int) -> Vector2:
	var seat: Seat = _seats[player]
	return seat.global_position + Vector2(seat.size.x * 0.5, seat.avatar_size * 0.5)

func _make_card(row: int, col: int, width: float = HAND_W) -> Card:
	var c := CardScene.instantiate() as Card
	c.card_width = int(width)
	c.row = row
	c.col = col
	return c

## At match end, lay each opponent's remaining hand face-up as a small vertical
## stack under their avatar, so you can see what they were holding. Cleared on the
## next deal. (Seat 0 is the human, whose own fan already shows their cards.)
func _reveal_opponent_hands(data: GameStateData, skip: int = -1) -> void:
	_clear_revealed()
	for p in _seats:
		if p == 0 or p == skip:
			continue
		var hand: Array = (data.hands[p] as Array).duplicate()
		if hand.is_empty():
			continue
		hand.sort_custom(func(a: Array, b: Array) -> bool: return _rank(a[1]) < _rank(b[1]))
		var seat: Seat = _seats[p]
		var cx := seat.global_position.x + seat.size.x * 0.5 - REVEAL_W * 0.5
		var top := seat.global_position.y + seat.size.y + 6.0
		for i in hand.size():
			var c := _make_card(hand[i][0], hand[i][1], REVEAL_W)
			c.position = Vector2(cx, top + i * REVEAL_STEP)
			c.z_index = 6
			c.modulate.a = 0.0
			add_child(c)
			_revealed.append(c)
			# Stagger a quick fade-in so the stack "deals" open.
			var tw := create_tween()
			tw.tween_interval(i * 0.04)
			tw.tween_property(c, "modulate:a", 1.0, 0.2)

func _clear_revealed() -> void:
	for c in _revealed:
		if is_instance_valid(c):
			c.queue_free()
	_revealed.clear()

## Is the [row, col] card present in `list`?
func _card_in(list: Array, card: Array) -> bool:
	for c in list:
		if c[0] == card[0] and c[1] == card[1]:
			return true
	return false

## Sâm Lốc rank order (3<4<…<K<A<2). Sheet cols: 0=A, 1=2, 2=3 … 12=K.
func _rank(col: int) -> int:
	if col == 0:
		return 12  # Ace
	if col == 1:
		return 13  # Two (highest)
	return col - 1

# --- input ----------------------------------------------------------------

func _on_card_input(event: InputEvent, card: Card) -> void:
	# Cards can be picked/lifted any time (even while waiting), so you can line up
	# a play before your turn comes round. Playing them is still gated on your turn
	# by the disabled PLAY button.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var sel: bool = not _selected.get(card, false)
		_selected[card] = sel
		card.position.y = -SELECT_LIFT if sel else 0.0
		# Keep the fan's natural draw order (right card on top of its left
		# neighbour) so a lifted card only overlays the card to its LEFT — the
		# next card to the right stays clear and easy to tap.
		card.z_index = 0

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
		_warn("Chọn bài trước khi đánh")
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
	_bao_passed = []
	for _p in _seats:
		_bao_passed.append(false)
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
	for p in _seats:
		if p != 0:
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
	await get_tree().create_timer(randf_range(0.4, 1.4)).timeout
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
	_play_btn.variant = PixelButton.Variant.GOLD
	_pass_btn.text = "THÔI"
	_set_my_turn(false)   # _start_turn re-enables them for whoever leads

# --- editor preview (no GameState in the editor) --------------------------

func _editor_preview() -> void:
	var counts := {0: 10, 1: 9, 2: 9, 3: 1}
	var money := {0: 8080, 1: 8080, 2: 8080, 3: 8080}
	for p in _seats:
		_seats[p].card_count = counts[p]
		_seats[p].balance = money[p]
		_seats[p].active = false
	_seats[0].active = true
	_seats[0].turn_progress = 0.7
	_build_hand_from([[2, 0], [0, 12], [2, 11], [1, 9], [0, 8], [3, 7], [3, 6], [1, 4], [2, 3], [0, 2]])
	last_played = [[1, 8], [3, 8]]
	_rebuild_last_played()
