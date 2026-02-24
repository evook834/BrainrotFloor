## File organization policy

## Command execution preference

- Do not run validation/build/test commands unless the user explicitly asks for them.
- This includes CI scripts (for example `scripts/ci/build_and_validate_places.sh`) and ad-hoc validation commands (for example `rojo sourcemap`, `rojo build`, or test suites).
- Default behavior: implement requested code changes first, then stop.

Do NOT force single-file implementations.
Do NOT force split-by-default refactors either.

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
