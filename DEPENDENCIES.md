# Dependencies — Table of contents (human & AI)

This document describes where code lives, how places are built, and **dependency rules** (who may `require` what). Use it to decide where to add code and what a script is allowed to depend on. **When you add or change runtime surfaces or dependency rules, update this file** (and PROJECT_MAP/README/REMOTES as needed; see [README § Maintaining the docs](README.md#maintaining-the-docs-dependencies-project_map-readme-remotes)).

---

## Repo layout

### New unified source (`src/`)

- **`src/ReplicatedStorage/Shared/`** — Replicated to client and server (config, catalogs, remote names).
- **`src/ServerScriptService/Shared/`** — Server-only shared (e.g. matchmaking config, place role).
- **`src/ServerScriptService/Lobby/`** — Lobby place server scripts (entry point for lobby systems).
- **`src/PlayerScriptService/SharedClient/`** — Client-only shared (e.g. sprint, settings, friends).
- **`src/ui/`** — New UI system with State-based management.

### Legacy structure (`game/`)

- **`game/shared/`** — Legacy shared (migrating to `src/`).
- **`game/lobby/`** — Legacy lobby place.
- **`game/match/`** — Legacy match place.

Each place has a **`default.project.json`** that mounts **`../shared`** into the same DataModel, so at runtime:
- **ReplicatedStorage.Shared** ← `src/ReplicatedStorage/Shared` or `game/shared/src/ReplicatedStorage/Shared`
- **ServerScriptService.Shared** ← `src/ServerScriptService/Shared` or `game/shared/src/ServerScriptService/Shared`
- **StarterPlayer.SharedClient** ← `src/PlayerScriptService/SharedClient` or `game/shared/src/StarterPlayerScripts/SharedClient`

---

## Dependency rules

### 1. Client cannot require server

- Scripts that run on the **client** (under **StarterPlayer.StarterPlayerScripts**, i.e. `*Client*` or **SharedClient**) **must not** `require` any module that lives under **ServerScriptService**.
- On the client, **ServerScriptService** is not available; requiring it would error. All client–server interaction goes through **Remotes** (see [REMOTES.md](REMOTES.md)).

### 2. Server can require shared and place server

- Scripts under **ServerScriptService** (Shared, Lobby, Match) **may** `require`:
  - **ReplicatedStorage.Shared** (e.g. `GameConfig`, `RemoteNames`),
  - **ServerScriptService.Shared** (e.g. `MatchmakingConfig`, `PlaceRole`),
  - Sibling or child modules in the same place (e.g. Match services requiring each other).

### 3. ReplicatedStorage.Shared is shared-only

- Modules under **ReplicatedStorage.Shared** are loaded on **both** client and server.
- They **must only** `require` other modules under **ReplicatedStorage.Shared** (e.g. `GameConfig` requiring `ClassSystemConfig`, `RemoteNames`, etc.).
- They **must not** `require` anything from **ServerScriptService** or **StarterPlayerScripts** (those trees are not shared or are one-sided).

### 4. ServerScriptService.Shared is server-only shared

- Modules under **ServerScriptService.Shared** may `require` **ReplicatedStorage.Shared** and other **ServerScriptService.Shared** modules.
- They **must not** `require` place-specific server code (Lobby/Match); place code may require Shared, not the other way around if you want to keep Shared place-agnostic.

### 5. Place-specific server

- **ServerScriptService.Lobby** may `require` **ReplicatedStorage.Shared**, **ServerScriptService.Shared**, and sibling Lobby modules. It **must not** require Match code (place-specific code may require shared, not vice versa).

### 6. Place-specific client

- **SharedClient** scripts may `require` **ReplicatedStorage.Shared** and sibling/client shared code. They **must not** `require` **ServerScriptService** or **ServerStorage**.

### 7. Communication across client–server boundary

- **Only via Remotes.** No cross-boundary `require`. Remote names and payloads are documented in [REMOTES.md](REMOTES.md).

---

## Quick reference: who can require what

| Consumer (who runs)        | May require |
|---------------------------|-------------|
| **ReplicatedStorage.Shared** | Only **ReplicatedStorage.Shared** |
| **ServerScriptService.Shared** | **ReplicatedStorage.Shared**, **ServerScriptService.Shared** |
| **ServerScriptService.Lobby / Match** | **ReplicatedStorage.Shared**, **ServerScriptService.Shared**, same place (e.g. Match services) |
| **StarterPlayerScripts** (any client) | **ReplicatedStorage.Shared**, same-place client modules only. **Never** ServerScriptService / ServerStorage |

---

## Related docs

- **[REMOTES.md](REMOTES.md)** — Remote names, direction (C→S / S→C), and payloads (including `WaveState` / `WaveEnemiesRemaining` from the wave director).
- **[AGENTS.md](AGENTS.md)** — File organization and when to add or edit files.
- **[UI_SYSTEM.md](UI_SYSTEM.md)** — New state-based UI system documentation.
