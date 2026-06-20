@tool
class_name Seat
extends Control

## A player seat: rounded avatar frame + count badge + name plate.
## One layout for everyone — name below, count badge on the top-right corner.
## `active` marks whose turn it is: the avatar bobs and its frame border becomes
## a depleting ember ring driven by `turn_progress` (the turn countdown, running
## out at the top-right). A seat holding one card (`card_count == 1`) glows red
## as a danger marker. Rendering only — no rules, no timing.

const FONT: Font = preload("res://assets/fonts/dearpix.ttf")
const NUM_FONT: Font = preload("res://assets/fonts/Pixelta.ttf")  # numerals: card count + balance
const GAP := 8.0
const BADGE := 40.0
const RADIUS := 18.0
const BORDER := 6.0
const BOB_AMP := 10.0       # how high the active avatar hops (px)
const BOB_PERIOD := 2.2     # seconds per hop
const PULSE_PERIOD := 2.6   # seconds per danger/aura pulse (slow breathe)
const AURA_ALPHA := Vector2(0.12, 0.32)   # soft glow opacity range
const AURA_SIZE := Vector2(8.0, 14.0)     # soft glow blur range (px)
const DANGER_PROGRESS := 0.5   # last 10s of a 20s turn: ring reddens

@export var hero_name: String = "SERAPHINE":
	set(v):
		hero_name = v
		_refresh()
@export var card_count: int = 10:
	set(v):
		card_count = v
		_update_processing()
		queue_redraw()
## Whose turn it is: ember ring + bobbing animation on this avatar.
@export var active: bool = false:
	set(v):
		active = v
		_update_processing()
		queue_redraw()
## Turn countdown, 1.0 = full ring, 0.0 = empty. Drawn only when `active`.
@export_range(0.0, 1.0) var turn_progress: float = 1.0:
	set(v):
		turn_progress = clampf(v, 0.0, 1.0)
		queue_redraw()
@export var show_badge: bool = true:
	set(v):
		show_badge = v
		queue_redraw()
@export var avatar_size: float = 96.0:
	set(v):
		avatar_size = v
		_refresh()
## Optional hero portrait; drawn inside the frame when set.
@export var avatar: Texture2D = null:
	set(v):
		avatar = v
		queue_redraw()
## Player money, shown as a coin + amount under the name.
@export var balance: int = 8080:
	set(v):
		balance = v
		_refresh()

const NAME_SIZE := 34      # readable on an HD phone screen, not tiny pixels
const BAL_SIZE := 38       # bigger so digits read clearly (0 vs 8) at a glance
const NAME_H := 42.0
const BAL_H := 46.0
const COIN_R := 11.0       # little coin glyph radius (tracks the bigger balance)
const COIN_GAP := 8.0      # coin -> number spacing

var _t := 0.0

func _ready() -> void:
	_refresh()
	_update_processing()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

## Animate while it's our turn or while we're in danger (the red aura pulses).
func _update_processing() -> void:
	if is_node_ready():
		set_process(active or card_count == 1)

func _refresh() -> void:
	var plate := _plate_size()
	custom_minimum_size = Vector2(maxf(avatar_size, plate.x), avatar_size + GAP + plate.y)
	queue_redraw()

## Name line over a coin+balance line; width fits the wider of the two.
func _plate_size() -> Vector2:
	var nw := FONT.get_string_size(hero_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, NAME_SIZE).x
	var bw := COIN_R * 2.0 + COIN_GAP + _bal_text_width()
	return Vector2(maxf(nw, bw) + 28.0, NAME_H + BAL_H)

func _bal_text_width() -> float:
	return NUM_FONT.get_string_size(_commas(balance), HORIZONTAL_ALIGNMENT_LEFT, -1.0, BAL_SIZE).x

func _draw() -> void:
	var bob := 0.0
	if active:
		bob = -BOB_AMP * (0.5 - 0.5 * cos(_t * TAU / BOB_PERIOD))
	var ax := (size.x - avatar_size) * 0.5
	var av := Rect2(Vector2(ax, bob), Vector2(avatar_size, avatar_size))

	_draw_avatar(av)
	if show_badge:
		_draw_badge(av)
	_draw_plate(av)

func _draw_avatar(av: Rect2) -> void:
	# Dark rounded outline behind the frame.
	var outline := StyleBoxFlat.new()
	outline.anti_aliasing = false
	outline.bg_color = Palette.OUTLINE
	outline.set_corner_radius_all(int(RADIUS + 3.0))
	if active:
		# Soft ember glow while it's our turn.
		var pulse := 0.5 + 0.5 * sin(_t * TAU / PULSE_PERIOD)
		outline.shadow_color = Color(Palette.EMBER, lerpf(AURA_ALPHA.x, AURA_ALPHA.y, pulse))
		outline.shadow_size = int(lerpf(AURA_SIZE.x, AURA_SIZE.y, pulse))
	draw_style_box(outline, av.grow(3.0))

	var frame := StyleBoxFlat.new()
	frame.anti_aliasing = false
	frame.bg_color = Palette.FRAME
	frame.set_corner_radius_all(int(RADIUS))
	frame.set_border_width_all(int(BORDER))
	# When active, the border is a dark track so the orange ember timer drawn on
	# top of it stands out clearly (spent = dark, remaining = bright ember).
	frame.border_color = Palette.OUTLINE if active else Palette.BEVEL_HI
	draw_style_box(frame, av)

	if avatar:
		draw_texture_rect(avatar, av.grow(-BORDER), false)

	if active:
		_draw_turn_ring(av)

## Depleting ember border tracing the frame's rounded-rect perimeter clockwise
## from the top-right corner; the gap (the "used up" time) opens at the top-right.
func _draw_turn_ring(av: Rect2) -> void:
	if turn_progress <= 0.0:
		return
	# Trace along the border centre-line so the ring sits on the frame edge.
	var inset := BORDER * 0.5
	var pts := _rr_points(av.grow(-inset), RADIUS - inset, 8)
	var n := pts.size()
	# Walk the perimeter by ARC LENGTH (not point index) so the ember end moves
	# at constant speed; interpolate the final segment for continuous motion.
	var total := 0.0
	for i in n - 1:
		total += pts[i].distance_to(pts[i + 1])
	var want := turn_progress * total
	var out := PackedVector2Array([pts[0]])
	var acc := 0.0
	for i in n - 1:
		var d := pts[i].distance_to(pts[i + 1])
		if acc + d <= want:
			out.append(pts[i + 1])
			acc += d
		else:
			var t := (want - acc) / d if d > 0.0 else 0.0
			out.append(pts[i].lerp(pts[i + 1], t))
			break
	if out.size() >= 2:
		# Last 10s of a 20s turn (progress <= 0.5): ring snaps to red.
		var col := Palette.BADGE_RED if turn_progress < DANGER_PROGRESS else Palette.EMBER
		draw_polyline(out, col, BORDER, false)

## Points tracing a rounded rect clockwise, starting at the top edge's right end
## (the top-right corner). `seg` = arc subdivisions per corner.
func _rr_points(rect: Rect2, rad: float, seg: int) -> PackedVector2Array:
	var r := clampf(rad, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var x1 := rect.position.x
	var y1 := rect.position.y
	var x2 := rect.position.x + rect.size.x
	var y2 := rect.position.y + rect.size.y
	var pts := PackedVector2Array()
	# top-right corner: up -> right
	_arc(pts, Vector2(x2 - r, y1 + r), r, -PI * 0.5, 0.0, seg)
	# bottom-right corner: right -> down
	_arc(pts, Vector2(x2 - r, y2 - r), r, 0.0, PI * 0.5, seg)
	# bottom-left corner: down -> left
	_arc(pts, Vector2(x1 + r, y2 - r), r, PI * 0.5, PI, seg)
	# top-left corner: left -> up
	_arc(pts, Vector2(x1 + r, y1 + r), r, PI, PI * 1.5, seg)
	# close back to the start (top edge, right end)
	pts.append(Vector2(x2 - r, y1))
	return pts

func _arc(pts: PackedVector2Array, center: Vector2, rad: float, a0: float, a1: float, seg: int) -> void:
	for i in seg + 1:
		var a: float = lerpf(a0, a1, float(i) / seg)
		pts.append(center + Vector2(cos(a), sin(a)) * rad)

func _draw_badge(av: Rect2) -> void:
	# Centred on the avatar's top-right corner so it sits half outside the frame.
	var danger := card_count == 1
	var bc := av.position + Vector2(av.size.x, 0.0)
	var fill := Palette.BADGE_RED if danger else Palette.COIN
	var ink := Palette.GOLD_HI if danger else Color("241208")
	if danger:
		# Soft pulsing red aura — same blurred glow as the turn aura.
		var pulse := 0.5 + 0.5 * sin(_t * TAU / PULSE_PERIOD)
		var glow := StyleBoxFlat.new()
		glow.anti_aliasing = false
		glow.bg_color = Color(Palette.BADGE_RED, 0.0)   # invisible box; only its shadow shows
		glow.set_corner_radius_all(int(BADGE * 0.5))
		glow.shadow_color = Color(Palette.BADGE_RED, lerpf(AURA_ALPHA.x, AURA_ALPHA.y, pulse))
		glow.shadow_size = int(lerpf(AURA_SIZE.x, AURA_SIZE.y, pulse))
		draw_style_box(glow, Rect2(bc - Vector2(BADGE, BADGE) * 0.5, Vector2(BADGE, BADGE)))
	draw_circle(bc, BADGE * 0.5 + 4.0, Palette.OUTLINE)
	draw_circle(bc, BADGE * 0.5, fill)
	PixelDraw.text_centered(self, Rect2(bc - Vector2(BADGE, BADGE) * 0.5, Vector2(BADGE, BADGE)),
			NUM_FONT, 30, str(card_count), ink)

func _draw_plate(_av: Rect2) -> void:
	var top := avatar_size + GAP
	# Name line — gold-hi, centred under the avatar.
	PixelDraw.text_centered(self, Rect2(0.0, top, size.x, NAME_H),
			FONT, NAME_SIZE, hero_name, Palette.GOLD_HI)
	# Balance line — a small coin glyph + amount, centred as a group below.
	var bal := _commas(balance)
	var group := COIN_R * 2.0 + COIN_GAP + _bal_text_width()
	var bx := (size.x - group) * 0.5
	var by := top + NAME_H - 10.0   # tuck the balance up closer to the name
	var cc := Vector2(bx + COIN_R, by + BAL_H * 0.5)
	# Outline + inner dot share one shade, just a touch darker than the coin.
	var coin_dk := Palette.COIN.darkened(0.18)
	draw_circle(cc, COIN_R + 3.0, coin_dk)
	draw_circle(cc, COIN_R, Palette.COIN)
	draw_circle(cc, COIN_R * 0.4, coin_dk)
	PixelDraw.text_centered(self, Rect2(bx + COIN_R * 2.0 + COIN_GAP, by, _bal_text_width(), BAL_H),
			NUM_FONT, BAL_SIZE, bal, Palette.GOLD)

func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if n < 0 else out
