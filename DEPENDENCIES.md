# Dependencies — Table of contents (human & AI)

This document describes where code lives, how places are built, and **dependency rules** (who may `require` what). Use it to decide where to add code and what a script is allowed to depend on. **When you add or change runtime surfaces or dependency rules, update this file** (and PROJECT_MAP/README/REMOTES as needed; see [README § Maintaining the docs](README.md#maintaining-the-docs-dependencies-project_map-readme-remotes)).

---

## Repo layout

Single Rojo project: **`default.project.json`** at repo root. Runtime mapping:

| Runtime path | Source path |
|--------------|-------------|
| **ReplicatedStorage.Shared** | `src/ReplicatedStorage/Shared/` |
| **ReplicatedStorage.ui** | `src/ui/` |
| **ReplicatedStorage.Packages** | `Packages/` |
| **ServerScriptService.Shared** | `src/ServerScriptService/Shared/` |
| **ServerScriptService.Features** | `src/ServerScriptService/Features/` |
| **StarterPlayer.StarterPlayerScripts** (ClientEntry, ClientMain, SharedClient, LobbyClient, Features) | `src/PlayerScriptService/` |
| **Workspace.DifficultyButtons** | `src/Workspace/DifficultyButtons/` |

### Source tree (`src/`)

- **`src/ReplicatedStorage/Shared/`** — Replicated to client and server (config, catalogs, remote names).
- **`src/ReplicatedStorage/` + `src/ui/`** — UI tree mounted at **ReplicatedStorage.ui** (GameStateMachine, UIManager, React Luau views); client entry requires it.
- **`src/ServerScriptService/Shared/`** — Server-only shared (matchmaking, PlaceRole, PlayerData, Settings, Friends).
- **`src/ServerScriptService/Features/`** — Place-specific server: Lobby (matchmaker, lobby settings, class remotes), Core (GameBootstrap, remotes, match systems), Waves, Shop, Enemies, Classes, etc. PlaceRole determines which run (Lobby vs Match).
- **`src/PlayerScriptService/`** — Client scripts: ClientEntry, ClientMain, SharedClient (settings, friends, movement, HUD), Features (match + LobbyClient).

---

## Dependency rules

### 1. Client cannot require server

- Scripts that run on the **client** (under **StarterPlayer.StarterPlayerScripts**, i.e. `*Client*` or **SharedClient**) **must not** `require` any module that lives under **ServerScriptService**.
- On the client, **ServerScriptService** is not available; requiring it would error. All client–server interaction goes through **Remotes** (see [REMOTES.md](REMOTES.md)).

### 2. Server can require shared and Features

- Scripts under **ServerScriptService** (Shared, Features) **may** `require`:
  - **ReplicatedStorage.Shared** (e.g. `GameConfig`, `RemoteNames`),
  - **ServerScriptService.Shared** (e.g. `MatchmakingConfig`, `PlaceRole`, `PlayerDataService`),
  - **ServerScriptService.Features** (sibling or child modules, e.g. Features.Lobby, Features.Core.Bootstrap).

### 3. ReplicatedStorage.Shared is shared-only

- Modules under **ReplicatedStorage.Shared** are loaded on **both** client and server.
- They **must only** `require` other modules under **ReplicatedStorage.Shared** (e.g. `GameConfig` requiring `ClassSystemConfig`, `RemoteNames`, etc.).
- They **must not** `require` anything from **ServerScriptService** or **StarterPlayerScripts** (those trees are not shared or are one-sided).

### 4. ServerScriptService.Shared is server-only shared

- Modules under **ServerScriptService.Shared** may `require` **ReplicatedStorage.Shared** and other **ServerScriptService.Shared** modules.
- They **must not** `require` **ServerScriptService.Features**; Features may require Shared, not the other way around (Shared stays place-agnostic).

### 5. ServerScriptService.Features (place-specific server)

- **ServerScriptService.Features** (Lobby, Core, Waves, Shop, Enemies, etc.) may `require` **ReplicatedStorage.Shared**, **ServerScriptService.Shared**, and sibling Features modules. PlaceRole (place ID) controls which systems run (e.g. Lobby vs match).

### 6. Client scripts

- Scripts under **StarterPlayerScripts** (ClientEntry, ClientMain, SharedClient, LobbyClient, Features) may `require` **ReplicatedStorage.Shared**, **ReplicatedStorage.ui**, and sibling client modules. They **must not** `require` **ServerScriptService** or **ServerStorage**.

### 7. Communication across client–server boundary

- **Only via Remotes.** No cross-boundary `require`. Remote names and payloads are documented in [REMOTES.md](REMOTES.md).

---

## Quick reference: who can require what

| Consumer (who runs)        | May require |
|---------------------------|-------------|
| **ReplicatedStorage.Shared** | Only **ReplicatedStorage.Shared** |
| **ServerScriptService.Shared** | **ReplicatedStorage.Shared**, **ServerScriptService.Shared** |
| **ServerScriptService.Features** | **ReplicatedStorage.Shared**, **ServerScriptService.Shared**, **ServerScriptService.Features** (siblings) |
| **StarterPlayerScripts** (any client) | **ReplicatedStorage.Shared**, **ReplicatedStorage.ui**, same-place client modules. **Never** ServerScriptService / ServerStorage |

---

## Related docs

- **[REMOTES.md](REMOTES.md)** — Remote names, direction (C→S / S→C), and payloads.
- **[README.md](README.md)** — Architecture overview, key systems, quick start.
- **[PROJECT_MAP.md](PROJECT_MAP.md)** — Folder-by-folder layout.
- **[AGENTS.md](AGENTS.md)** — File organization and when to add or edit files.
- **[UI_SYSTEM.md](UI_SYSTEM.md)** — State-based UI system (GameStateMachine, UIManager).
