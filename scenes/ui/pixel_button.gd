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

var _hover := false
var _pressed := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hover = false; _pressed = false; queue_redraw())

func _gui_input(event: InputEvent) -> void:
	if variant == Variant.DISABLED:
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
	var disabled := variant == Variant.DISABLED

	# Hard drop shadow (hidden while pressed / disabled).
	if not _pressed and not disabled:
		draw_rect(Rect2(Vector2(0.0, DROP), face_size), Palette.OUTLINE)

	var face_y := DROP if _pressed else 0.0
	var face := Rect2(Vector2(0.0, face_y), face_size)

	var fill := Palette.GOLD
	var ink := Palette.BTN_INK
	match variant:
		Variant.GOLD:
			fill = Palette.GOLD_HI if _hover else Palette.GOLD
			ink = Palette.BTN_INK
		Variant.CRIMSON:
			fill = Palette.FELT if _hover else Palette.TABLE_HI
			ink = Palette.GOLD_HI
		Variant.DISABLED:
			fill = Palette.FRAME
			ink = Color("7d5f33")

	if disabled:
		# single muted border, no bevel
		draw_rect(Rect2(face.position - Vector2(4, 4), face.size + Vector2(8, 8)), Palette.OUTLINE)
		draw_rect(face, fill)
		draw_rect(Rect2(face.position, Vector2(face.size.x, 6)), Color("5a4420"))
		draw_rect(Rect2(face.position, Vector2(6, face.size.y)), Color("5a4420"))
	else:
		PixelDraw.beveled(self, face, fill, Palette.BEVEL_HI, Palette.BEVEL_LO, Palette.OUTLINE)

	PixelDraw.text_centered(self, face, FONT, font_size, text, ink)
