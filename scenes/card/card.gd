@tool
class_name Card
extends Control

## Reusable card view backed by the Cards.png sprite sheet.
## Pure presentation: it reads row/col + width and shows the matching cell.
## No game rules live here — callers decide which card to display.
##
## Sheet layout: 13 columns x 5 rows, each cell 48x64.
## Columns: 0=A, 1=2, 2=3, ... 12=K.  Rows 0-3 = suits, row 4 = card backs.
##
## Faces and the back all come from the deck sheet (cards.png). The standard
## face-down back is the navy [4][2] cell. (The stacked-deck pile image,
## deck_stack.png, is a separate rarely-used asset and is not handled here.)

const SHEET: Texture2D = preload("res://assets/cards/cards.png")
const CELL := Vector2(48, 64)
const COLS := 13
const ROWS := 5
## Navy back cell on the sheet, used for face-down cards.
const BACK_CELL := Vector2(2, 4)  # col 2, row 4

@export_range(0, ROWS - 1) var row: int = 0:
	set(v):
		row = clampi(v, 0, ROWS - 1)
		_apply()
@export_range(0, COLS - 1) var col: int = 0:
	set(v):
		col = clampi(v, 0, COLS - 1)
		_apply()
@export_range(24, 160) var card_width: int = 60:
	set(v):
		card_width = v
		_apply()
@export var shadow: bool = true:
	set(v):
		shadow = v
		_apply()
## When true, show the navy card back instead of the row/col face.
@export var face_down: bool = false:
	set(v):
		face_down = v
		_apply()

@onready var _face: TextureRect = $Face
@onready var _shadow: TextureRect = $Shadow

func _ready() -> void:
	_apply()

## Height derived from the cell aspect (matches the HTML: w * 64/48).
func card_height() -> float:
	return float(card_width) * CELL.y / CELL.x

## The texture to display: the navy back cell when face-down, else the face cell.
func _card_texture() -> AtlasTexture:
	var cell := BACK_CELL if face_down else Vector2(col, row)
	var at := AtlasTexture.new()
	at.atlas = SHEET
	at.region = Rect2(cell * CELL, CELL)
	return at

func _apply() -> void:
	if _face == null or _shadow == null:
		return
	var card_size := Vector2(float(card_width), card_height())
	custom_minimum_size = card_size

	# Shadow: a tinted copy of the card sitting a few px lower, behind the face.
	# Approximates the CSS drop-shadow without a blur (crisp pixels).
	var offset := maxf(2.0, roundf(card_size.y * 0.05))
	var tex := _card_texture()
	_shadow.visible = shadow
	_shadow.texture = tex if shadow else null
	_shadow.size = card_size
	_shadow.position = Vector2(0.0, offset)
	_shadow.modulate = Color("180810", 0.55)

	_face.texture = tex
	_face.size = card_size
	_face.position = Vector2.ZERO
