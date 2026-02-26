# Brainrot Floor

Co-op wave-based shooter on Roblox: players choose a difficulty in the **lobby**, get matched into a **match** server, then survive waves of enemies, buy weapons and ammo, level classes, and optionally return to lobby or vote for the next map after game over.

This README is an **architecture overview**. For folder-by-folder layout see [PROJECT_MAP.md](PROJECT_MAP.md). For dependency rules see [DEPENDENCIES.md](DEPENDENCIES.md). For remotes see [REMOTES.md](REMOTES.md). For feature notes (sprint, stamina, difficulty, game over, etc.) see [doc.md](doc.md).

---

## Architecture overview

### Two places, one shared tree

- **Lobby place** (`game/lobby/`) — Players pick difficulty (Easy / Normal / Hard). Server uses **MemoryStore** to find or create a match server and teleports the party there.
- **Match place** (`game/match/`) — Wave loop, enemies, shop, classes, difficulty scaling, settings, ammo pickups. When all players die, game over triggers; players can return to lobby or vote for the next map.
- **Shared** (`game/shared/`) — Code used by both places, split by runtime:
  - **ReplicatedStorage.Shared** — Config and catalogs (waves, enemies, classes, shop, player, remotes). Replicated to client and server; may only `require` within this tree.
  - **ServerScriptService.Shared** — Server-only shared (matchmaking config, place role detection).
  - **StarterPlayerScripts.SharedClient** — Client-only shared (e.g. sprint/stamina).

Each place has a Rojo **`default.project.json`** that mounts **`../shared`** into the same DataModel, so at runtime one place = one game tree with both place-specific and shared scripts.

### Client / server boundary

- **Clients** run under `StarterPlayer.StarterPlayerScripts` (SharedClient + LobbyClient or MatchClient). They **cannot** `require` anything under `ServerScriptService`; it does not exist on the client.
- **Servers** run under `ServerScriptService` (Shared + Lobby or Match). They may `require` ReplicatedStorage.Shared and ServerScriptService (shared + place).
- **All cross-boundary communication** is via **Remotes** only (RemoteEvent / RemoteFunction). Names and payloads are defined in [REMOTES.md](REMOTES.md) and `ReplicatedStorage.Shared.Remotes.RemoteNames`.

### Key systems (match)

| System | Server | Client | Remotes (examples) |
|--------|--------|--------|--------------------|
| **Waves** | WaveService: state machine (Preparing → InProgress → Cleared / Blocked / GameOver) plus KF-style director (WaveTotalTarget + AliveCap, composition, 1500 cap), intermission | WaveHud: wave number, state, intermission countdown, game-over overlay, map vote UI | WaveState (S→All) |
| **Classes** | ClassService: selection, XP, levels, combat bonuses; persistence via DataService (PlayerDataService) | ClassUi, XpBarHud | ClassGetData, ClassSelect, ClassState (C→S / S→C) |
| **Shop** | ShopService: catalog per player, buy weapon/ammo, trader prompt | ShopUi | ShopOpen (S→C), ShopGetCatalog, ShopBuyWeapon, ShopBuyAmmo (C→S) |
| **Combat** | Weapon fire/reload/aim handlers, damage, ammo | Crosshair, AmmoHud, DamageIndicators, DualWieldPose | WeaponAim, WeaponFire, WeaponReload (C→S), DamageIndicator (S→C) |
| **Enemies** | EnemyService, EnemyAIService, EnemyVfxService, difficulty-scaled HP/damage | EnemyHealthBars, EnemyDeathCloud | — |
| **Settings** | Shared SettingsService: get/save via DataService (audio, HUD) | SettingsUi (lobby + match) | SettingsGet (C→S), SettingsSave (C→S) |
| **Ammo pickups** | AmmoPickupService: zones, spawn/respawn, pickup | — | — |
| **Game over / map vote** | GameBootstrap: all-dead → GameOver, return-to-lobby teleport, map vote winner → reserve + teleport party | WaveHud: game-over overlay, return button, map vote panel | ReturnToLobby, MapVote (reserved) |

Config (wave timing, enemy counts, wave director tables (WaveTotalTarget/AliveCap/composition), class catalog, weapon catalog, difficulty multipliers, etc.) lives in **ReplicatedStorage.Shared** (e.g. `GameConfig`, `WaveConfig`, `ClassCatalog`, `WeaponCatalog`). Server-only shared config (place IDs, MemoryStore name, difficulties) is in **ServerScriptService.Shared.Matchmaking**.

### Lobby

- **LobbyMatchmaker**: Listens for difficulty buttons, finds/creates match server via MemoryStore, teleports party with difficulty in teleport data.
- **LobbySettings** / **SettingsService**: Expose SettingsGet / SettingsSave so settings persist across lobby and match.
- **PlaceRole**: Detects Lobby vs Match so lobby-only systems (matchmaker) and match-only systems (waves, shop, classes, etc.) run in the correct place.

---

## Repo layout (summary)

```
game/
├── shared/          # ReplicatedStorage.Shared, ServerScriptService.Shared, SharedClient
├── lobby/           # Lobby place (ServerScriptService.Lobby, LobbyClient)
├── match/           # Match place (ServerScriptService.Match, MatchClient)
└── places/          # Legacy; prefer lobby/ and match/ for current code
```

Detailed folder-by-folder breakdown: **[PROJECT_MAP.md](PROJECT_MAP.md)**.

---

## Quick start

1. **Toolchain** — `aftman` (see `aftman.toml`), `rojo`, `wally` for packages.
2. **Serve a place** — e.g. `rojo serve game/lobby/default.project.json` or `rojo serve game/match/default.project.json`.
3. **Studio** — Install Rojo plugin, connect to the served port (e.g. `localhost:34872`), sync.
4. **Matchmaking** — Set `LOBBY_PLACE_ID` and `MATCH_PLACE_IDS` in `game/shared/src/ServerScriptService/Shared/Matchmaking/MatchmakingConfig.luau` for real place IDs.
5. **Packages** — Per-place: `cd game/lobby && wally install`, `cd game/match && wally install` (if needed).

---

## Docs index

| Doc | Purpose |
|-----|--------|
| **[README.md](README.md)** | Architecture overview (this file). |
| **[PROJECT_MAP.md](PROJECT_MAP.md)** | Folder-by-folder summary. |
| **[DEPENDENCIES.md](DEPENDENCIES.md)** | Who may `require` what; client vs server; shared vs place. |
| **[REMOTES.md](REMOTES.md)** | Remote names, direction, payloads. |
| **[AGENTS.md](AGENTS.md)** | Agent instructions: command preference, placement rules, file organization, when to add/edit/split. |

---

## Maintaining the docs (DEPENDENCIES, PROJECT_MAP, README, REMOTES)

These four files describe where code lives and how it connects. Keep them accurate when the codebase changes.

**When to update**

- **Prefer updating as part of the same change.** When you add, remove, or move a module, script, folder, or remote, update the affected doc(s) in that same task:
  - New or moved **script/folder** → [PROJECT_MAP.md](PROJECT_MAP.md) (and README key systems table if it’s a new system or major move).
  - New or changed **remote** → [REMOTES.md](REMOTES.md) and `RemoteNames.luau`.
  - New **runtime surface** or dependency rule → [DEPENDENCIES.md](DEPENDENCIES.md) if the “who can require what” table or repo layout changes.
  - New **system** or major flow change → [README.md](README.md) architecture / key systems section.
- **Optional:** A periodic or end-of-session pass (e.g. once a day) over the four docs can catch drift if something was missed during a change. The primary rule is still: update whenever you add/remove/move modules, remotes, or layout so the docs stay in sync.
