class_name PixelDraw
extends RefCounted

## Shared immediate-mode helpers for the chunky beveled pixel look.
## Drawn into a CanvasItem's _draw(): outer outline, fill, two-tone bevel edges.

## Beveled panel: dark outline ring, flat fill, light top/left + dark bottom/right.
static func beveled(ci: CanvasItem, r: Rect2, fill: Color, hi: Color, lo: Color,
		outline: Color, bevel: float = 6.0, ow: float = 4.0) -> void:
	if ow > 0.0:
		ci.draw_rect(Rect2(r.position - Vector2(ow, ow), r.size + Vector2(ow, ow) * 2.0), outline)
	ci.draw_rect(r, fill)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, bevel)), hi)                                   # top
	ci.draw_rect(Rect2(r.position, Vector2(bevel, r.size.y)), hi)                                   # left
	ci.draw_rect(Rect2(r.position + Vector2(0.0, r.size.y - bevel), Vector2(r.size.x, bevel)), lo)  # bottom
	ci.draw_rect(Rect2(r.position + Vector2(r.size.x - bevel, 0.0), Vector2(bevel, r.size.y)), lo)  # right

## Draw text centered inside a rect.
static func text_centered(ci: CanvasItem, r: Rect2, font: Font, size: int,
		text: String, color: Color) -> void:
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
	var pos := r.position + (r.size - ts) * 0.5 + Vector2(0.0, font.get_ascent(size))
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)
