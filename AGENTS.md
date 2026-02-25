# Repository agent instructions

## Command execution preference

- Do not run validation/build/test commands unless the user explicitly asks for them.
- This includes CI scripts (for example `scripts/ci/build_and_validate_places.sh`) and ad-hoc validation commands (for example `rojo sourcemap`, `rojo build`, or test suites).
- Default behavior: implement requested code changes first, then stop.

---

## Response length

- By default, give minimal output: confirm what was done in one short line (e.g. “Done.” or “Added X.”). Only add caveats or errors if relevant.
- Give longer explanations, summaries, or step-by-step breakdowns only when the user explicitly asks (e.g. “explain”, “summarize”, “why did you…”).
- This reduces token use and keeps replies focused unless the user wants detail.

---

## Placement: use the layout docs

**Do not** put new features or modules in a single unrelated file, or scatter multiple single files in the wrong place. **Do** create a new script (and folder if needed) in the **correct** location.

Before adding or moving code:

1. **Consult [DEPENDENCIES.md](DEPENDENCIES.md)** — Client cannot require server; ReplicatedStorage.Shared only requires shared; etc. Put code in a tree that is allowed to depend on what it needs.
2. **Consult [PROJECT_MAP.md](PROJECT_MAP.md)** — Read each folder’s description and **decide** where the new code belongs by matching its responsibility to that folder. Place by logical fit; the map is a guide, not a strict list of allowed files.
3. **Consult [README.md](README.md)** — For high-level system ownership (which system owns waves, shop, classes, etc.) and where remotes are used.
4. **For new remotes** — Define names in `RemoteNames.luau`, document in [REMOTES.md](REMOTES.md), and create/bind in the appropriate server bootstrap.

When in doubt: create a **new** script (and folder if it's a new subsystem) in the location that matches the runtime (client vs server), place (lobby vs match vs shared), and dependency rules, then wire it (e.g. `require`, bootstrap, remotes). Do not dump new behavior into an existing file that belongs to a different feature or place.

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
  - avoid extracting tiny one-off modules (roughly 20-40 lines) unless they remove duplication or isolate high-volatility logic.

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
- Do not do repo-wide "find files to split" passes unless explicitly requested.
