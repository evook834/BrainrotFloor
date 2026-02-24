## Repository agent instructions

### Command execution preference

- Do not run validation/build/test commands unless the user explicitly asks for them.
- This includes CI scripts (for example `scripts/ci/build_and_validate_places.sh`) and ad-hoc validation commands (for example `rojo sourcemap`, `rojo build`, or test suites).
- Default behavior: implement requested code changes first, then stop.

### Additional policy source

- See `agent.md` for project-specific implementation policy.
