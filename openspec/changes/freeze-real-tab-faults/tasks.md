## 1. Build
- [x] 1.1 Freeze, hard and soft: one good ghost probe means an empty box (fixture: a placeholder that comes back after the probe; must-fail: a real draft)
- [x] 1.2 A session that moved to a new id in the same process keeps its registration; freeze and park follow it and update the entry (must-fail: another process on the tab, a registry that cannot be written)
- [x] 1.3 Freeze re-reads the session file right before `/exit`
- [x] 1.4 Real-tab check on throwaway tabs: freeze of a fresh session with the placeholder showing; freeze and thaw of a session after `/clear` (both passed on a tab without an issue; a tab bound to an issue is kept after `/clear`, because the run's record is a stub by then: open, fails safe)
