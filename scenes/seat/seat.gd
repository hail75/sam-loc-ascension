@tool
class_name Seat
extends Control

## A player seat: rounded avatar frame + count badge + name plate.
## One layout for everyone — name below, count badge on the top-right corner.
## `active` marks whose turn it is: the avatar bobs and its frame border becomes
## a depleting ember ring driven by `turn_progress` (the turn countdown, running
## out at the top-right). A seat holding one card (`card_count <= 1`) glows red
## as a danger marker. Rendering only — no rules, no timing.

const FONT: Font = preload("res://assets/fonts/dearpix.ttf")
const GAP := 8.0
const BADGE := 40.0
const RADIUS := 18.0
const BORDER := 6.0
const BOB_AMP := 10.0       # how high the active avatar hops (px)
const BOB_PERIOD := 2.2     # seconds per hop
const PULSE_PERIOD := 1.6   # seconds per danger/aura pulse

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
		set_process(active or card_count <= 1)

func _refresh() -> void:
	var plate := _plate_size()
	custom_minimum_size = Vector2(maxf(avatar_size, plate.x), avatar_size + GAP + plate.y)
	queue_redraw()

func _plate_size() -> Vector2:
	var ts := FONT.get_string_size(hero_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24)
	return Vector2(ts.x + 28.0, 40.0)

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
		outline.shadow_color = Color(Palette.EMBER, lerpf(0.25, 0.6, pulse))
		outline.shadow_size = int(lerpf(10.0, 20.0, pulse))
	draw_style_box(outline, av.grow(3.0))

	var frame := StyleBoxFlat.new()
	frame.anti_aliasing = false
	frame.bg_color = Palette.FRAME
	frame.set_corner_radius_all(int(RADIUS))
	frame.set_border_width_all(int(BORDER))
	# Base border colour; the active ember ring is drawn on top as a depleting arc.
	frame.border_color = Palette.BEVEL_HI
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
	var pts := _rr_points(av.grow(-inset), RADIUS - inset, 6)
	var n := pts.size()
	var k := int(round(turn_progress * (n - 1)))
	if k >= 1:
		draw_polyline(pts.slice(0, k + 1), Palette.EMBER, BORDER, false)

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
	var danger := card_count <= 1
	var bc := av.position + Vector2(av.size.x, 0.0)
	var fill := Palette.BADGE_RED if danger else Palette.COIN
	var ink := Palette.GOLD_HI if danger else Color("241208")
	if danger:
		# Pulsing red aura around the badge.
		var pulse := 0.5 + 0.5 * sin(_t * TAU / PULSE_PERIOD)
		draw_circle(bc, BADGE * 0.5 + lerpf(8.0, 16.0, pulse), Color(Palette.BADGE_RED, lerpf(0.15, 0.35, pulse)))
	draw_circle(bc, BADGE * 0.5 + 4.0, Palette.OUTLINE)
	draw_circle(bc, BADGE * 0.5, fill)
	PixelDraw.text_centered(self, Rect2(bc - Vector2(BADGE, BADGE) * 0.5, Vector2(BADGE, BADGE)),
			FONT, 26, str(card_count), ink)

func _draw_plate(av: Rect2) -> void:
	var plate := _plate_size()
	# Name below the avatar — text only, no box.
	var pr := Rect2(Vector2((size.x - plate.x) * 0.5, avatar_size + GAP), plate)
	PixelDraw.text_centered(self, pr, FONT, 24, hero_name, Palette.GOLD_HI)
