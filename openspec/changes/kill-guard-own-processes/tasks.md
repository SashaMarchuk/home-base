## 1. Measure
- [x] 1.1 Whether a PreToolUse `ask` is honoured in `bypassPermissions` mode (headless run, a spawned `sleep`)

## 2. Build
- [x] 2.1 bash-guard: ownership check for exact ids (descendant of the agent session, or a live registry entry), ask or refuse for the rest, refuse when undetermined
- [x] 2.2 codex-pre-tool marks the surface so the guard never answers `ask` to Codex
- [x] 2.3 Fixtures with real spawned processes: own, foreign, registry (live, changed, closed, adopted, unreadable), signal 0, no `ps`, both surfaces
