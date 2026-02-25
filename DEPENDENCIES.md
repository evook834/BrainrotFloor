# Dependencies — Table of contents (human & AI)

This document describes where code lives, how places are built, and **dependency rules** (who may `require` what). Use it to decide where to add code and what a script is allowed to depend on. **When you add or change runtime surfaces or dependency rules, update this file** (and PROJECT_MAP/README/REMOTES as needed; see [README § Maintaining the docs](README.md#maintaining-the-docs-dependencies-project_map-readme-remotes)).

---

## Repo layout

- **`game/shared/`** — Shared code used by multiple places. Split by runtime:
  - **`src/ReplicatedStorage/Shared/`** — Replicated to client and server (config, catalogs, remote names).
  - **`src/ServerScriptService/Shared/`** — Server-only shared (e.g. matchmaking config, place role).
  - **`src/StarterPlayerScripts/SharedClient/`** — Client-only shared (e.g. sprint).
- **`game/lobby/`** — Lobby place. Place-specific server under **`src/ServerScriptService/Lobby/`**, client under **`src/StarterPlayer/StarterPlayerScripts/LobbyClient/`**.
- **`game/match/`** — Match place. Place-specific server under **`src/ServerScriptService/Match/`**, client under **`src/StarterPlayer/StarterPlayerScripts/MatchClient/`**.
- **`game/places/`** — Legacy/copy of place-specific code; see repo structure for current locations.

Each place has a **`default.project.json`** that mounts **`../shared`** into the same DataModel, so at runtime:
- **ReplicatedStorage.Shared** ← `game/shared/src/ReplicatedStorage/Shared`
- **ServerScriptService.Shared** ← `game/shared/src/ServerScriptService/Shared`
- **StarterPlayer.StarterPlayerScripts.SharedClient** ← `game/shared/src/StarterPlayerScripts/SharedClient`
- **ServerScriptService.Lobby** / **Match** and **LobbyClient** / **MatchClient** come from the place project (lobby or match).

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

### 5. Place-specific client

- **LobbyClient** / **MatchClient** scripts may `require` **ReplicatedStorage.Shared** and sibling/client shared code. They **must not** `require` **ServerScriptService** or **ServerStorage**.

### 6. Communication across client–server boundary

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

- **[REMOTES.md](REMOTES.md)** — Remote names, direction (C→S / S→C), and payloads.
- **[AGENTS.md](AGENTS.md)** — File organization and when to add or edit files.
