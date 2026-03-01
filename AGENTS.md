# Repository agent instructions

Guidance for AI and human contributors. Treat as **orientation** — follow unless context clearly suggests otherwise.

---

## Command execution preference

- Do not run validation/build/test commands unless the user explicitly asks for them (e.g. “run tests”, “make sure it builds”, “validate”).
- When the user does ask, run the relevant command (e.g. `rojo build`, `rojo sourcemap`, CI script, test suite).
- This includes CI scripts (e.g. `scripts/ci/build_and_validate_places.sh`) and ad-hoc validation. Default: implement requested code changes first, then stop.

---

## Response length

- By default, give minimal output: confirm what was done in one short line (e.g. “Done.” or “Added X.”). Only add caveats or errors if relevant.
- Give longer explanations, summaries, or step-by-step breakdowns only when the user explicitly asks (e.g. “explain”, “summarize”, “why did you…”).
- This reduces token use and keeps replies focused unless the user wants detail.

---

## Placement: use the layout docs

Prefer putting new features or modules in the **right** location (new script and folder if needed) rather than in an unrelated file or scattered single files.

Before adding or moving code:

1. **Consult [DEPENDENCIES.md](DEPENDENCIES.md)** — Client cannot require server; ReplicatedStorage.Shared only requires shared; etc. Put code in a tree that is allowed to depend on what it needs.
2. **Consult [PROJECT_MAP.md](PROJECT_MAP.md)** — Read each folder’s description and **decide** where the new code belongs by matching its responsibility to that folder. Place by logical fit; the map is a guide, not a strict list of allowed files.
3. **Consult [README.md](README.md)** — For high-level system ownership (which system owns waves, shop, classes, etc.) and where remotes are used.
4. **For new remotes** — Define names in `RemoteNames.luau`, document in [REMOTES.md](REMOTES.md) (payloads, directions), and create/bind in the appropriate server bootstrap.

When in doubt: create a **new** script (and folder if it's a new subsystem) in the location that matches the runtime (client vs server), place (lobby vs match vs shared), and dependency rules, then wire it (e.g. `require`, bootstrap, remotes). Do not dump new behavior into an existing file that belongs to a different feature or place. If two folders could fit, choose one and stay consistent.

When you add, move, or remove modules, folders, or remotes, update the relevant docs (see [README § Maintaining the docs](README.md#maintaining-the-docs)).

---

## Shared vs place-specific code

When code is needed in **both** Lobby and Match, put the implementation in a **shared** tree and use thin place-specific entry scripts that require and run it (with options if behavior differs by place). When code is needed in **only one** place, keep it in the place-specific area.

- **Used in both places** → Implement once under a shared tree: `src/ServerScriptService/Shared/`, `src/PlayerScriptService/SharedClient/`, or `src/ReplicatedStorage/Shared/` as appropriate. Each place has a small script that requires the shared module and invokes it (e.g. `Service.start()`, or `ClassUi.run({ isLobby = true })`). Pass options or config for place-specific behavior instead of duplicating logic.
- **Used in one place only** → Keep the module and launcher in the place-specific area (e.g. `Features/LobbyClient/` for lobby-only, or other `Features/` subfolders for match). No shared module required.

Applies to UI, client logic, and server logic. Prefer one shared module plus thin launchers over duplicating implementation.

---

## File organization policy

Do NOT force single-file implementations. Do NOT force split-by-default refactors either.

When implementing a change, decide whether to:
1. edit existing files,
2. create new files, or
3. create new files and update existing wiring (`require`s, service startup registration, remotes/config exports).

### Decision rules

- Prefer editing existing files when:
  - functionality naturally belongs there (same feature/module or place),
  - there is already an established pattern to extend (service module, HUD script, shared config),
  - the change is small and keeps the file readable,
  - splitting would add indirection without a clear ownership benefit.

- Prefer creating a new file when:
  - introducing a new module/service/utility that is reusable or logically separate,
  - adding a new Roblox runtime surface (new server service, client HUD/controller, or shared config/catalog module),
  - separation improves testability or avoids circular dependencies,
  - the existing file is already hard to navigate, and there is a clear responsibility boundary for extraction.
  - at least one concrete reuse signal exists (used by a second caller now, or highly likely to be reused in near-term follow-up work).
  - Only extract small one-off modules (e.g. 20–40 lines) when they remove duplication or isolate high-volatility logic.

- Prefer doing both (new file + edits) when:
  - new logic belongs in a new module but must be wired into existing entry points (`require` wiring, bootstrapping, remotes, registries),
  - refactoring is needed to keep responsibilities separated.
  - keep existing public APIs stable unless an API change is explicitly requested.

### Size guidance (soft, not automatic)

- Size alone is not sufficient reason to split a file.
- Use line count as a signal, not a rule:
  - shared modules: consider splitting around >300-400 lines if responsibilities are mixed,
  - match services and complex client HUD scripts can remain larger when behavior is tightly coupled.
- If a split is considered, define the responsibility boundary first, then split.

### Constraints

- Follow existing folder structure and naming conventions.
- Keep changes minimal and localized (avoid broad rewrites unless required).
- If a new file is created, also add/adjust required `require` wiring, exports, and references accordingly.
- Avoid repo-wide "find files to split" or refactor-everything passes unless the user requests them.

---

## UI: view vs controller (front vs back)

Some UI is built with **React Luau** under `src/ui/UI/` (e.g. ShopView); the rest uses the pattern below. See [UI_SYSTEM.md](UI_SYSTEM.md) for GameStateMachine, UIManager, and state-driven visibility.

For client UI that builds instances and has non-trivial logic (remotes, state, payload handling), prefer splitting into:

- **View (front)** — One module that only builds the UI tree (`Instance.new` for ScreenGui, frames, buttons, labels, etc.). Expose a single builder (e.g. `build()`) that returns a view table: refs to key instances (panel, buttons, list container, status label, etc.) and optional helpers that only touch instances (e.g. `showPanel()`, `hidePanel()`, `setStatus(text, color)`). No remotes, no game logic, no payload parsing.
- **Controller (back)** — A module that requires the view, calls the builder to get refs, then handles all behavior: remotes, event wiring, payload handling, rendering list rows, open/close flow. The controller updates the view via the refs and helpers.

Keep a single public entry (e.g. `ClassUi.luau`) that requires the controller and re-exports `run(options)` so existing launchers stay unchanged. When adding or refactoring UI, put instance construction in the view and all logic in the controller. See [UI_SYSTEM.md](UI_SYSTEM.md) for state machine, UIManager, and GameState.
