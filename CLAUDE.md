# CLAUDE.md — Sâm Lốc: Ascension

## What this is
A 2D pixel-art mobile card game: the Northern-Vietnamese game **Sâm Lốc**, reskinned
in Western high-fantasy. Vietnamese rules and vocabulary stay proudly visible; Western
fantasy art is the frame. Named after *báo sâm* — declaring an unbeatable hand.

Targets: **iOS + Android** (mobile-first), with **web export** as a playtest channel.

## Tech & architecture
- **Engine/client:** Godot 4.6, GDScript. **Compatibility renderer** (OpenGL ES 3 /
  WebGL2 — widest device reach, required for web export). Do not switch to
  Forward+/Mobile.

### Current phase: OFFLINE-FIRST
For now the game runs **entirely offline** — all game rules, logic, and state live in
the client so the game is fully playable on-device (vs bots / local) with no network.

**But build for the eventual move to an authoritative server.** Later, game logic will
move to a Python/FastAPI WebSocket server that becomes the single source of truth. To
make that migration painless:
- Write the **rules engine as pure, self-contained GDScript classes** — no `Node`,
  no UI, no scene-tree dependencies. It takes game state + an action, returns new state.
- Keep rules/logic **strictly separate** from rendering and input. UI scripts call into
  the rules module; they never embed rules themselves.
- Route all state changes through one clear path (e.g. a `GameState` module) so a network
  layer can later replace the local one without touching the UI.
- Don't scatter scoring/validation across scene scripts — it must be portable as one unit.

## Repo conventions
- Same Godot **4.6** on every machine (Ubuntu + Mac). `.godot/` is gitignored
  (regenerated cache); commit `.tscn`, `.gd`, `.tres`, source assets, and `*.import`
  sidecars.
- Pixel art: import textures with filter **Nearest**, mipmaps **off** (crisp pixels).
- Scenes are `.tscn`; reusable pieces (card, seat, button) are their own scenes.
- Keep `.gd` scripts limited to rendering + input plumbing; rules live in the standalone
  rules module, not in node scripts.

## Design system (authoritative palette — use exact hex)
- felt `#7a1226` · table `#6a0f20` · frame `#3d0a14` · outline `#180810` · ember `#ef8b2c`
- gold `#d8b24a` · gold-dk `#b8902f` · gold-hi `#f0d68a`
- card-face `#cfc7be` · pip-red `#781e37`
- Fonts: **DearPix** for display/numerals and body/labels.
- Aesthetic: warm, rich, polished pixel art. Portrait phone, base resolution **720×1280**,
  stretch mode `canvas_items`, aspect `expand`.

## Assets
**Do not invent or generate art assets — use the existing ones.** Splash art and sprites
are finished. Wire up what's there.

## Guardrails for Claude Code
- Keep the rules engine portable: pure GDScript classes, no Node/UI dependencies, so it
  can move server-side later without a rewrite.
- Don't mix rules/logic into rendering or UI scripts.
- Don't build features/screens beyond what's asked.
- Don't change the renderer, palette hex, base resolution, or Godot version.
- Don't invent art assets.
- Don't commit `.godot/`.
- Ask before adding dependencies/plugins; prefer stock Godot 4.6.
- Match existing pixel-art import settings (Nearest, no mipmaps) for any new texture.
