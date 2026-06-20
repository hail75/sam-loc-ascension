@tool
class_name PixelButton
extends Control

## Beveled pixel button (PLAY / PASS / etc). Pure rendering + input plumbing:
## it draws the chunky bevel + hard drop shadow and emits `pressed`. No game
## logic lives here.

signal pressed

enum Variant { GOLD, CRIMSON, DISABLED }

const FONT: Font = preload("res://assets/fonts/dearpix.ttf")
const DROP := 10.0  # hard drop-shadow depth; also the press travel
const ROUND := 16.0  # crisp pixel corner radius
const ROUND_STEP := 4.0  # size of each corner stair

@export var text: String = "PLAY":
	set(v):
		text = v
		queue_redraw()
@export var variant: Variant = Variant.GOLD:
	set(v):
		variant = v
		queue_redraw()
@export var font_size: int = 36:
	set(v):
		font_size = v
		queue_redraw()
## Greys the button out and blocks input (e.g. when it isn't your turn), while
## keeping its colour variant so it restores cleanly.
@export var disabled: bool = false:
	set(v):
		disabled = v
		_pressed = false
		queue_redraw()

var _pressed := false

func _is_off() -> bool:
	return disabled or variant == Variant.DISABLED

## Mute a colour toward its own grey and dim it — "greyed out" but still
## recognisably gold/crimson.
func _greyed(c: Color) -> Color:
	var l := c.get_luminance()
	return c.lerp(Color(l, l, l), 0.55).darkened(0.3)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Mobile-first: no hover state. Cancel the press if the finger drags off.
	mouse_exited.connect(func() -> void:
		if _pressed:
			_pressed = false
			queue_redraw())

func _gui_input(event: InputEvent) -> void:
	if _is_off():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			queue_redraw()
		elif _pressed:
			_pressed = false
			queue_redraw()
			if Rect2(Vector2.ZERO, size).has_point(event.position):
				pressed.emit()

func _draw() -> void:
	var face_size := Vector2(size.x, size.y - DROP)
	var off := _is_off()

	# Hard drop shadow (hidden while pressed / disabled).
	if not _pressed and not off:
		PixelDraw.pixel_round_rect(self, Rect2(Vector2(0.0, DROP), face_size),
			Palette.OUTLINE, ROUND, ROUND_STEP)

	var face_y := DROP if _pressed else 0.0
	var face := Rect2(Vector2(0.0, face_y), face_size)

	var fill := Palette.GOLD
	var ink := Palette.BTN_INK
	match variant:
		Variant.GOLD:
			fill = Palette.GOLD
			ink = Palette.BTN_INK
		Variant.CRIMSON:
			fill = Palette.TABLE_HI
			ink = Palette.GOLD_HI
		Variant.DISABLED:
			fill = Palette.FRAME
			ink = Color("7d5f33")
	if off:
		# Grey out the button's OWN colour: desaturate + dim, keep the hue.
		fill = _greyed(fill)
		ink = _greyed(ink)

	if off:
		# single muted border, no bevel
		PixelDraw.pixel_round_rect(self, Rect2(face.position - Vector2(4, 4), face.size + Vector2(8, 8)),
			Palette.OUTLINE, ROUND + 4.0, ROUND_STEP)
		PixelDraw.pixel_round_rect(self, face, fill, ROUND, ROUND_STEP)
		draw_rect(Rect2(face.position + Vector2(ROUND, 0.0), Vector2(face.size.x - ROUND * 2.0, 6)), fill.darkened(0.3))
		draw_rect(Rect2(face.position + Vector2(0.0, ROUND), Vector2(6, face.size.y - ROUND * 2.0)), fill.darkened(0.3))
	else:
		PixelDraw.beveled_round(self, face, fill, Palette.BEVEL_HI, Palette.BEVEL_LO,
			Palette.OUTLINE, 6.0, 4.0, ROUND, ROUND_STEP)

	_draw_label(face, ink)

## Centered label with a hard pixel drop-shadow (embossed look).
func _draw_label(face: Rect2, ink: Color) -> void:
	# DearPix has near-symmetric side bearings, so plain advance-width centering
	# reads optically centered for most words — no flat fudge (it shoved short
	# words like THÔI visibly right). The exception is "ĐÁNH": the barred Đ
	# overhangs left, pulling the ink left of centre, so nudge just that word right.
	const OPTICAL_NUDGE := {"ĐÁNH": 4.0}
	var nudge_x: float = OPTICAL_NUDGE.get(text, 0.0)
	const SHADOW := Vector2(3.0, 4.0)
	var ts := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var pos := face.position + (face.size - ts) * 0.5 \
		+ Vector2(nudge_x, FONT.get_ascent(font_size))
	# Emboss with a colour that actually contrasts the ink: a light highlight
	# under dark text (gold button), a dark shadow under light text (crimson).
	# (A dark shadow behind dark ink is invisible — which is the bug.)
	if not _is_off():
		var emboss := Palette.GOLD_HI if ink.get_luminance() < 0.45 else Palette.OUTLINE
		draw_string(FONT, pos + SHADOW, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			font_size, emboss)
	draw_string(FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, ink)
