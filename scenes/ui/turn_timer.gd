@tool
class_name TurnTimer
extends Control

## Conic countdown ring (the mockup's turn timer). Rendering only — a caller
## sets `progress` (1.0 = full) and `value` (the number shown). No timing logic.

const FONT: Font = preload("res://assets/fonts/dearpix.ttf")

@export_range(0.0, 1.0) var progress: float = 0.7:
	set(v):
		progress = clampf(v, 0.0, 1.0)
		queue_redraw()
@export var value: String = "12":
	set(v):
		value = v
		queue_redraw()
@export var inner_color: Color = Palette.TABLE_LO:
	set(v):
		inner_color = v
		queue_redraw()
@export var font_size: int = 32:
	set(v):
		font_size = v
		queue_redraw()

func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	draw_circle(c, r, Palette.OUTLINE)        # outline ring
	draw_circle(c, r - 4.0, Palette.FRAME)    # unfilled track

	if progress > 0.0:
		var pts := PackedVector2Array([c])
		var steps := 48
		var start := -PI * 0.5
		for i in steps + 1:
			var a: float = lerpf(start, start + TAU * progress, float(i) / steps)
			pts.append(c + Vector2(cos(a), sin(a)) * (r - 4.0))
		draw_colored_polygon(pts, Palette.EMBER)

	draw_circle(c, r - 14.0, inner_color)     # sunken disc
	PixelDraw.text_centered(self, Rect2(Vector2.ZERO, size), FONT, font_size, value, Palette.GOLD_HI)
