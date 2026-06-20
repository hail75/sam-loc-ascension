@tool
class_name TableChrome
extends Control

## Static, non-interactive table chrome: menu glyph, "last played" label, and
## the YOUR TURN banner. (The player avatar/pill is its own Seat.)
## Pure drawing; values are pushed in by the table controller.

const FONT: Font = preload("res://assets/fonts/dearpix.ttf")

@export var banner_text: String = "LƯỢT CỦA BẠN":
	set(v):
		banner_text = v
		queue_redraw()

func _draw() -> void:
	# Authored in 720x1280 space; this Control fills the (height-expanding)
	# viewport, so top items pin to the top, the middle group tracks the
	# vertical centre, and the player row pins to the bottom.
	var cy := size.y * 0.5
	_menu(Rect2(size.x - 84.0, 24.0, 60.0, 60.0))
	_banner(cy + 20.0, banner_text)

func _menu(r: Rect2) -> void:
	draw_rect(r.grow(4.0), Palette.OUTLINE)
	draw_rect(r, Palette.BEVEL_HI)
	draw_rect(r.grow(-4.0), Palette.FRAME)
	for i in 3:
		draw_rect(Rect2(r.position + Vector2(14.0, 18.0 + i * 10.0), Vector2(32.0, 4.0)), Palette.GOLD)

func _banner(y: float, text: String) -> void:
	if text.is_empty():
		return
	var cx := size.x * 0.5
	var ts: Vector2 = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 64)
	var box := Rect2(0.0, y, size.x, 80.0)
	PixelDraw.text_centered(self, Rect2(box.position + Vector2(6.0, 6.0), box.size), FONT, 64, text, Palette.OUTLINE)
	PixelDraw.text_centered(self, box, FONT, 64, text, Palette.GOLD_HI)
	var half := ts.x * 0.5
	var ly := y + 40.0
	draw_rect(Rect2(36.0, ly, (cx - half - 20.0) - 36.0, 6.0), Palette.OUTLINE)
	var rx := cx + half + 20.0
	draw_rect(Rect2(rx, ly, (size.x - 36.0) - rx, 6.0), Palette.OUTLINE)
