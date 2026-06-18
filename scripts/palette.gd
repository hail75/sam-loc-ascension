class_name Palette
extends RefCounted

## Authoritative Royal Crimson palette (exact hex from CLAUDE.md / mockup).
## Presentation constants only — referenced by UI scripts so the hex never drifts.

const FELT := Color("7a1226")
const TABLE := Color("6a0f20")
const FRAME := Color("3d0a14")
const OUTLINE := Color("180810")
const EMBER := Color("ef8b2c")
const GOLD := Color("d8b24a")
const GOLD_DK := Color("b8902f")
const GOLD_HI := Color("f0d68a")
const CARD_FACE := Color("cfc7be")
const PIP_RED := Color("781e37")

# Supporting shades used by the mockup's frames/bevels.
const BEVEL_HI := Color("9a7a34")  # top/left bevel
const BEVEL_LO := Color("4e3812")  # bottom/right bevel
const TABLE_HI := Color("5e1320")  # raised table / panels
const TABLE_LO := Color("46101b")  # sunken inner (timer disc)
const COIN := Color("c69a36")
const TEXT_MUTE := Color("c79a4e")
const BTN_INK := Color("1a0d04")   # dark text on gold
const BADGE_RED := Color("cc1f2e") # active/leader badge
