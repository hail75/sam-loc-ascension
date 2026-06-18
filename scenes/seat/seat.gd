@tool
class_name Seat
extends Control

## A player seat: rounded beveled avatar frame + count badge + name plate.
## Reused for opponents (badge + name below) and for the player (label to the
## right, no badge, `active` = your-turn ember aura + bob). Rendering only.

const FONT: Font = preload("res://assets/fonts/dearpix.ttf")
const GAP := 8.0
const BADGE := 40.0
const RADIUS := 18.0
const BORDER := 6.0
const BOB_AMP := 10.0       # how high the active avatar hops (px)
const BOB_PERIOD := 2.2     # seconds per hop
const PULSE_PERIOD := 1.6   # seconds per aura pulse

@export var hero_name: String = "SERAPHINE":
	set(v):
		hero_name = v
		_refresh()
@export var card_count: int = 10:
	set(v):
		card_count = v
		queue_redraw()
## Red glowing badge (low-card / danger marker, e.g. the mockup's Seraphine).
@export var leader: bool = false:
	set(v):
		leader = v
		queue_redraw()
## Whose turn it is: ember aura + bobbing animation on this avatar.
@export var active: bool = false:
	set(v):
		active = v
		if is_node_ready():
			set_process(v)
		queue_redraw()
@export var show_badge: bool = true:
	set(v):
		show_badge = v
		queue_redraw()
## false = name plate below the avatar; true = label to the right (player style).
@export var label_right: bool = false:
	set(v):
		label_right = v
		_refresh()
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
	set_process(active)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _refresh() -> void:
	var plate := _plate_size()
	if label_right:
		custom_minimum_size = Vector2(avatar_size + GAP + plate.x, maxf(avatar_size, plate.y))
	else:
		custom_minimum_size = Vector2(maxf(avatar_size, plate.x), avatar_size + GAP + plate.y)
	queue_redraw()

func _plate_size() -> Vector2:
	var ts := FONT.get_string_size(hero_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24)
	return Vector2(ts.x + 28.0, 40.0)

func _draw() -> void:
	var bob := 0.0
	if active:
		bob = -BOB_AMP * (0.5 - 0.5 * cos(_t * TAU / BOB_PERIOD))
	var ax := 0.0 if label_right else (size.x - avatar_size) * 0.5
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
	draw_style_box(outline, av.grow(3.0))

	var frame := StyleBoxFlat.new()
	frame.anti_aliasing = false
	frame.bg_color = Palette.FRAME
	frame.set_corner_radius_all(int(RADIUS))
	frame.set_border_width_all(int(BORDER))
	frame.border_color = Palette.EMBER if active else Palette.BEVEL_HI
	if active:
		# Pulsing ember aura via the style box's soft shadow.
		var pulse := 0.5 + 0.5 * sin(_t * TAU / PULSE_PERIOD)
		frame.shadow_color = Color(Palette.EMBER, lerpf(0.25, 0.6, pulse))
		frame.shadow_size = int(lerpf(10.0, 20.0, pulse))
	draw_style_box(frame, av)

	if avatar:
		draw_texture_rect(avatar, av.grow(-BORDER), false)

func _draw_badge(av: Rect2) -> void:
	# Centred on the avatar's top-right corner so it sits half outside the frame.
	var bc := av.position + Vector2(av.size.x, 0.0)
	var fill := Palette.BADGE_RED if leader else Palette.COIN
	var ink := Palette.GOLD_HI if leader else Color("241208")
	if leader:
		draw_circle(bc, BADGE * 0.5 + 10.0, Color(Palette.BADGE_RED, 0.35))  # red glow
	draw_circle(bc, BADGE * 0.5 + 4.0, Palette.OUTLINE)
	draw_circle(bc, BADGE * 0.5, fill)
	PixelDraw.text_centered(self, Rect2(bc - Vector2(BADGE, BADGE) * 0.5, Vector2(BADGE, BADGE)),
			FONT, 26, str(card_count), ink)

func _draw_plate(av: Rect2) -> void:
	var plate := _plate_size()
	var pr: Rect2
	if label_right:
		# Vertically centred on the avatar's resting position (does not bob).
		pr = Rect2(Vector2(avatar_size + GAP, (avatar_size - plate.y) * 0.5), plate)
	else:
		pr = Rect2(Vector2((size.x - plate.x) * 0.5, avatar_size + GAP), plate)
	var border := Palette.EMBER if active else Palette.GOLD_DK
	draw_rect(pr, border)
	draw_rect(pr.grow(-2.0), Palette.OUTLINE)
	PixelDraw.text_centered(self, pr, FONT, 24, hero_name, Palette.GOLD_HI)
