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

### Code map (where things live)
- `rules/sam_loc_rules.gd` — **the engine**. Pure static `SamLocRules` (RefCounted):
  `deal / classify / is_valid / beats / apply / settle`. `(state, action) -> {ok, state,
  reason}`. Also holds an **offline-only reference bot** (`find_play`) — a heuristic, NOT
  authoritative rules; the future server drives real players instead.
- `rules/game_state_data.gd` — `GameStateData` (RefCounted): plain serialisable match state
  (`hands, current, table, table_owner, passed, finished, winner`) + `clone()`. No behaviour.
- `rules/deck.gd` — `Deck`: pure shuffled-deck helper.
- `autoload/game_state.gd` — `GameState` autoload: the single runtime path. Holds the live
  `GameStateData`, routes every action through `SamLocRules.apply`, emits signals
  (`dealt / played / passed / rejected / match_ended`). **Contains no game logic** — when the
  server arrives, only this file changes (apply locally → send over WebSocket → apply reply).
- `scenes/table/table_a.gd` — the playable table: presentation + input plumbing only. Renders
  state, reports taps, animates deal/play/win, runs bots on timers.

### Game rules (current build)
- **Card encoding:** a card is `[row, col]` into `Cards.png`. Rows 0–3 = suits (suits never
  affect ranking in this build); cols `0=A, 1=2, 2=3 … 12=K`.
- **Single-rank order:** `3 (low) … 10, J, Q, K, A, 2 (high)`.
- **Combos:** single, pair, triple, quad, straight (run ≥3). A response must match the
  table combo's TYPE and SIZE and outrank its key. **Chops:** a QUAD beats a single 2
  (1 quad > 1 two); a DOUBLE QUAD (two quads) beats a pair of 2s (2 quads > 2 twos).
- **Straights** run `A,2,3,…,10,J,Q,K,A` — may start on an ace or a deuce, end no higher than
  an ace, no wrap past the ace.
- **Trick / fold:** pass or timeout folds you for the rest of the trick (locked out until a
  new trick is led). Timeout == auto-pass. The previous match's winner leads the next deal.
- **Scoring:** winner +30, each loser −10.

## Repo conventions
- Same Godot **4.6** on every machine (Ubuntu + Mac). `.godot/` is gitignored
  (regenerated cache); commit `.tscn`, `.gd`, `.tres`, source assets, and `*.import`
  sidecars.
- Pixel art: import textures with filter **Nearest**, mipmaps **off** (crisp pixels).
- Scenes are `.tscn`; reusable pieces (card, seat, button) are their own scenes.
- Keep `.gd` scripts limited to rendering + input plumbing; rules live in the standalone
  rules module, not in node scripts.
- **Player-facing copy is Vietnamese** (`ĐÁNH` / `BỎ LƯỢT`, `LƯỢT CỦA BẠN`, `… THẮNG`, etc.).
  DearPix covers the diacritics. Keep engine reasons in English; translate them in the UI
  layer (see `WARN_VI` in `table_a.gd`).
- **Responsive layout:** stretch is `canvas_items` + `expand`, so the canvas is 720 wide on
  phones but grows (toward ~960) on squarer tablets and taller on thin phones. In layout
  code read the **live** size (`size.x` / `_vw()`), never hardcode 720; the felt/vignette
  must fill the real viewport. `_relayout()` (re-run on `resized`) spreads the seats and
  eases the player zone — keep it idempotent.
- **The Godot editor re-saves open `.tscn` files and will revert your file edits to them.**
  For volatile UI props (button text/size, etc.) set them from code in `_ready` so they
  survive; only commit `.tscn` changes when the scene isn't open in the editor.

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
