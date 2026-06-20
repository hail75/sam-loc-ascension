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

## Crisp pixel-rounded rect: corners are a square staircase (no anti-aliasing),
## following a quantised quarter-circle so it reads as "rounded" but stays pixel-
## sharp. `step` is the size of each corner stair (bigger = chunkier steps).
static func pixel_round_rect(ci: CanvasItem, r: Rect2, color: Color,
		radius: float, step: float = 4.0) -> void:
	radius = minf(radius, minf(r.size.x, r.size.y) * 0.5)
	if radius < step:
		ci.draw_rect(r, color)
		return
	# Straight middle section spanning between the rounded top/bottom caps.
	ci.draw_rect(Rect2(r.position + Vector2(0.0, radius),
			Vector2(r.size.x, r.size.y - radius * 2.0)), color)
	# Corner bands: each `step`-tall slice is inset by a quantised circle profile,
	# mirrored to the top and bottom caps.
	var y := 0.0
	while y < radius:
		var band := minf(step, radius - y)
		var dy := radius - (y + band * 0.5)
		var ix := radius - sqrt(maxf(0.0, radius * radius - dy * dy))
		ix = roundf(ix / step) * step
		var w := r.size.x - ix * 2.0
		ci.draw_rect(Rect2(r.position + Vector2(ix, y), Vector2(w, band)), color)
		ci.draw_rect(Rect2(r.position + Vector2(ix, r.size.y - y - band), Vector2(w, band)), color)
		y += step

## Like `beveled`, but with crisp pixel-stepped rounded corners. The bevel is
## layered as nested rounded rects so the highlight (top/left) and shadow
## (bottom/right) wrap the staircase corners instead of being clipped flat.
static func beveled_round(ci: CanvasItem, r: Rect2, fill: Color, hi: Color, lo: Color,
		outline: Color, bevel: float = 6.0, ow: float = 4.0,
		radius: float = 8.0, step: float = 4.0) -> void:
	if ow > 0.0:
		pixel_round_rect(ci, Rect2(r.position - Vector2(ow, ow), r.size + Vector2(ow, ow) * 2.0),
				outline, radius + ow, step)
	# Shadow base: the bottom/right bevel shows through this layer.
	pixel_round_rect(ci, r, lo, radius, step)
	# Highlight: anchored top-left, shrunk by the bevel so `lo` survives on the
	# bottom/right edges (and their rounded corner).
	pixel_round_rect(ci, Rect2(r.position, r.size - Vector2(bevel, bevel)), hi, radius, step)
	# Inner fill: inset on all sides, revealing the hi ring (top/left) and lo ring
	# (bottom/right), each following the corner staircase.
	pixel_round_rect(ci, Rect2(r.position + Vector2(bevel, bevel), r.size - Vector2(bevel, bevel) * 2.0),
			fill, maxf(0.0, radius - bevel), step)

## Draw text centered inside a rect.
static func text_centered(ci: CanvasItem, r: Rect2, font: Font, size: int,
		text: String, color: Color) -> void:
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
	var pos := r.position + (r.size - ts) * 0.5 + Vector2(0.0, font.get_ascent(size))
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)
