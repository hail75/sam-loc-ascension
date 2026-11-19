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
  (`hands, current, table, table_owner, passed, bao_sam, chop_level, den_feeder,
  foul_finish, an_trang_winner, finished, winner`) + `clone()`. No behaviour.
- `rules/deck.gd` — `Deck`: pure shuffled-deck helper.
- `autoload/game_state.gd` — `GameState` autoload: the single runtime path. Holds the live
  `GameStateData`, persistent `balances`, and `num_players`, routes every action through
  `SamLocRules.apply`, emits signals (`dealt / played / passed / chopped / rejected /
  match_ended`). **Contains no game logic** — when the server arrives, only this file changes
  (apply locally → send over WebSocket → apply reply).
- `scenes/table/table_a.gd` — the playable table: presentation + input plumbing only. Renders
  state, reports taps, animates deal/play/win, runs bots on timers.

### Session / elimination (offline)
- Everyone starts at **`START_BALANCE` = 1000**. Balances are zero-sum and persist across deals.
- The engine is **variable-player (2–4)**: `deal(rng, first, players)` and every per-player loop
  reads `state.hands.size()`, not the `NUM_PLAYERS` const (which is just the 4-max default).
- Between deals (`GameState._apply_elimination`, run at `new_match`): any **bot** at ≤0 coins
  busts out and the survivors re-index (you are always player 0). **You never leave** — if YOU
  hit ≤0, or only you'd remain, the table **resets to a fresh 4 players at 1000**.
- The table maps engine index → a fixed seat NODE per live count (`_build_seat_map`): 4p =
  you/right(Grimwald)/top(Vayne)/left(Seraphine); 3p drops the **top**; 2p also drops the
  **left**. Hidden seats stay positioned but invisible.

### Game rules (current build)
- **Card encoding:** a card is `[row, col]` into `Cards.png`. Rows 0–3 = suits (suits never
  affect ranking in this build); cols `0=A, 1=2, 2=3 … 12=K`.
- **Single-rank order:** `3 (low) … 10, J, Q, K, A, 2 (high)`.
- **Combos:** single, pair, triple, quad, straight (run ≥3). A response must match the
  table combo's TYPE and SIZE and outrank its key. **Chops:** a QUAD beats a single 2
  (1 quad > 1 two); a DOUBLE QUAD (two quads) beats a pair of 2s (2 quads > 2 twos); a
  higher QUAD beats a lower QUAD. Every chop triggers a **chặt** payment (see Scoring).
- **Finishing on a deuce is a foul (thối 2):** you *may* play an emptying hand that still
  holds a 2, but you **don't win** — the deal ends with no pot winner, you forfeit, and you
  pay **15 stake to each** other player (`foul_finish` state, settled via `feed`, captioned
  **THỐI**). Shed your 2s before the final play to actually win. During **báo sâm**, fouling
  on a 2 **fails the declaration** (báo sâm failure scoring applies; still captioned THỐI).
  Bots avoid fouling, taking it only when no other lead exists.
- **Đền (block obligation):** you "đền" **only** when BOTH conditions hold — (1) you play a
  single that **isn't your highest** (you still hold a higher single), and (2) the player
  with **one card left** beats *exactly that single* to go out **instantly, right after** you
  play it. Then you pay your own normal-loss amount to **each other loser** (everyone but the
  winner and you). Determined precisely at the winning play (`den_feeder` = the player whose
  single was beaten while holding a higher one); settled as the `feed` array from `settle`,
  popped as its own +/- beat *before* the pot, captioned **ĐỀN**. Playing your highest single,
  leading a combo, or any play the one-card player can't instantly beat — **never** đền.
  **Bots avoid it** by always answering/leading with their highest single when the next
  player holds one card.
- **Straights** run `A,2,3,…,10,J,Q,K,A` — may start on an ace or a deuce, end no higher than
  an ace, no wrap past the ace.
- **Trick / fold:** pass or timeout folds you for the rest of the trick (locked out until a
  new trick is led). Timeout == auto-pass. The previous match's winner leads the next deal.
- **Ăn trắng (instant win on the deal):** some dealt hands win on the spot (deuces allowed),
  ranked strongest→weakest: **3 triplets > 10-card straight > 5 pairs > 10-card single-colour
  flush (red rows 0–1 / black rows 2–3) > quad of deuces**. Checked right after dealing
  (`an_trang_tier`/`an_trang_plays`); if anyone qualifies, all buttons/timers freeze, each
  qualifying combo flies to the table in a **golden aura** (weakest first, strongest last),
  the banner reads "<PLAYER> ĂN TRẮNG", and the payout pops. Every tier first plays a
  **dark-fantasy splash** (a 16-frame strip from `assets/splash/`, chosen in
  `_an_trang_splash`): `3samco` 3 SÁM CÔ, `sanhrong` SẢNH RỒNG, `5doi` 5 ĐÔI,
  `fulldo`/`fullden` ĐỒNG HOA ĐỎ/ĐEN (by the flush's colour), `tuquy2` TỨ QUÝ 2 — dim + quake +
  a full-width character rising from the bottom under a palette-framed title banner; see
  `_play_combo_splash`. In play, a quad gets the banner-less `tuquy` knight, and a play that
  breaks a báo sâm gets the `chatsam` skull ("CHẶT SÂM") instead (`_breaks_bao_sam`,
  `_pre_fly_time` keeps the land/settle timers in sync).
  Scoring (like báo sâm): each
  loser pays a flat **20 stake**, winner sweeps it (+60 total). Money is deferred to
  `GameState.commit_an_trang()` (called at the +/- beat) so the deal
  shows pre-win balances. **DEBUG:** `GameState.AN_TRANG_DEBUG` forces Vayne (seat 2) to hold
  the four 2s every deal — turn OFF for real play.
- **Báo sâm (the namesake ritual):** before each deal there's a claim window. A player may
  declare *báo sâm* to grab the open right and lead; they must then win every trick
  **unblocked** (run the whole hand). Success → +20 stake from each opponent (+60 stake
  total); failure (their lead gets beaten, or they give up the lead) → −60 stake, +20 stake
  to each opponent. Declaring is engine state (`bao_sam`, action `"declare"`, settled in
  `settle(state)`). **Bots cannot báo sâm yet** — only the human, via the BÁO SÂM button in
  the pre-game window.
- **Scoring (winner-takes-all):** the **stake** is the money unit (10 coins for now; every
  amount is a multiple of it). Normal deal — the winner sweeps the whole pot; each loser
  pays **1 stake per card** still in hand **+ 5 stake per leftover 2 or quad**. A **móm**
  loser who never played a single card all deal (still holds the full 10-card hand) pays
  **15 stake for the cards instead of 10** (+ the 2/quad penalty on top). **Thối 2** — a foul
  finish wins no pot; the fouler pays **15 stake to each** other player (`feed`, no settle).
  **Đền** — see the block-obligation rule above (`feed`, paid out as its own beat before the
  pot). Báo sâm — see
  above. **Chặt:** the instant a 2/quad is bombed, the chopped player pays the chopper **15
  stake per chopped 2/quad**, times the chop chain's depth — a chop that chops a chop pays
  ×2, the next ×3, … (the chain resets each trick). Chặt are immediate side-payments
  (returned in `apply`'s `chops`, applied in `GameState`, popped with the +/- animation),
  separate from the end-of-deal `settle`.

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
  layer (see `_on_rejected` in `table_a.gd`).
- **Responsive layout:** stretch is `canvas_items` + `expand`, so the canvas is 720 wide on
  phones but grows (toward ~960) on squarer tablets and taller on thin phones. In layout
  code read the **live** size (`size.x` / `_vw()`), never hardcode 720; the felt/vignette
  must fill the real viewport. `_relayout()` (re-run on `resized`) spreads the seats and
  eases the player zone — keep it idempotent. It also insets the top row by
  `DisplayServer.get_display_safe_area()` so a punch-hole/notch can't clip the top seat.
- **Portrait is locked** via `display/window/handheld/orientation=1` so the phone can't
  auto-rotate.
- **The Godot editor re-saves open `.tscn` files AND `project.godot`, reverting your file
  edits to them.** For volatile UI props (button text/size, etc.) set them from code in
  `_ready` so they survive; for `project.godot` edit it with the editor CLOSED, or change it
  through the editor's Project Settings UI. (NB: the base resolution stays **720×1280** —
  with `canvas_items` stretch it's already pixel-scaled to the device, so bumping it to
  1080×1920 buys nothing visually and just forces a full layout rescale.)

## Design system (authoritative palette — use exact hex)
- felt `#7a1226` · table `#6a0f20` · frame `#3d0a14` · outline `#180810` · ember `#ef8b2c`
- gold `#d8b24a` · gold-dk `#b8902f` · gold-hi `#f0d68a`
- card-face `#cfc7be` · pip-red `#781e37`
- Fonts: **DearPix** for display/numerals and body/labels.
- Aesthetic: warm, rich, polished pixel art. Portrait phone, base resolution **720×1280**,
  stretch mode `canvas_items`, aspect `expand`. (All UI layout constants live in this
  720-wide design space.)

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
