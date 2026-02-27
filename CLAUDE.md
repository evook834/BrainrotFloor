# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Toolchain

- **Build/serve**: `rojo serve game/lobby/default.project.json` or `rojo serve game/match/default.project.json`
- **Package management**: `cd game/lobby && wally install` or `cd game/match && wally install`
- **Tools**: `aftman` manages rojo (7.6.1) and wally (0.3.2)
- **Tests**: Not run by default. Tests exist only in dependencies (signal, janitor, typed-promise).

## Architecture

**Two places, one shared tree**:
- **Lobby** (`game/lobby/`) — Difficulty selection, matchmaking, teleport to match
- **Match** (`game/match/`) — Wave combat, enemies, shop, classes, settings
- **Shared** (`game/shared/`) — Code used by both places

**Runtime layout via Rojo**:
```
ReplicatedStorage.Shared   ← game/shared/src/ReplicatedStorage/Shared (client+server)
ServerScriptService.Shared ← game/shared/src/ServerScriptService/Shared (server only)
StarterPlayer.SharedClient ← game/shared/src/StarterPlayerScripts/SharedClient (client only)
ServerScriptService.Lobby/Match ← place-specific server
StarterPlayer.LobbyClient/MatchClient ← place-specific client
```

## Dependency rules

1. **Client cannot require server** — Scripts under `StarterPlayer.StarterPlayerScripts` (any `*Client*`) must never require `ServerScriptService` modules. Use remotes instead.
2. **ReplicatedStorage.Shared is self-contained** — May only require other modules under `ReplicatedStorage.Shared`.
3. **ServerScriptService.Shared is place-agnostic** — May require `ReplicatedStorage.Shared` and sibling `ServerScriptService.Shared` modules, but not place-specific code.
4. **Place server** may require `ReplicatedStorage.Shared`, `ServerScriptService.Shared`, and sibling place server modules.

See `DEPENDENCIES.md` for full details.

## Remotes

All cross-boundary communication uses remotes defined in `ReplicatedStorage.Shared.Remotes.RemoteNames`. See `REMOTES.md` for:
- Remote names and directions (C→S / S→C / S→All)
- Payload schemas (e.g., `WaveState`, `ClassState`, `SettingsGet/Save`)
- Server-set attributes on the Remotes folder (`CurrentWaveState`, `CurrentWaveNumber`, etc.)

## File organization

**When adding/modifying code**:
1. Check `DEPENDENCIES.md` for allowed dependencies
2. Check `PROJECT_MAP.md` for correct folder location
3. Update `README.md`, `DEPENDENCIES.md`, `PROJECT_MAP.md`, `REMOTES.md` if the change affects architecture

**New UI with logic**: Split into View (front, builds UI tree) and Controller (back, handles remotes/logic). Entry module re-exports `run(options)`.

**When to split files**: Create new modules for reusable/subsystem code (>300-400 lines for shared, larger for match services), or when extracting improves testability/circular dependency resolution.

## Key systems (match)

| System | Server | Client | Remotes |
|--------|--------|--------|---------|
| Waves | WaveService (state machine, KF director, spawning) | WaveHud (state, countdown, game-over) | WaveState (S→All) |
| Classes | ClassService (selection, XP, persistence) | ClassUi, XpBarHud | ClassGetData, ClassSelect, ClassState |
| Shop | ShopService (catalog, purchase, inventory) | ShopUi | ShopOpen (S→C), ShopGetCatalog, ShopBuyWeapon/Ammo (C→S) |
| Combat | Weapon handlers, damage, ammo | Crosshair, AmmoHud, DamageIndicators | WeaponAim, WeaponFire, WeaponReload (C→S), DamageIndicator (S→C) |
| Enemies | EnemyService, AI, VFX | EnemyHealthBars, DeathCloud | — |
| Settings | SettingsService (via DataService) | SettingsUi (lobby + match) | SettingsGet, SettingsSave |

## Quick reference

- **Config/catalog** → `game/shared/src/ReplicatedStorage/Shared/`
- **Server-only shared** → `game/shared/src/ServerScriptService/Shared/`
- **Client-only shared** → `game/shared/src/StarterPlayerScripts/SharedClient/`
- **Lobby server** → `game/lobby/src/ServerScriptService/Lobby/`
- **Lobby client** → `game/lobby/.../LobbyClient/`
- **Match server** → `game/match/src/ServerScriptService/Match/` (subfolder by concern)
- **Match client** → `game/match/.../MatchClient/` (subfolder by concern)
