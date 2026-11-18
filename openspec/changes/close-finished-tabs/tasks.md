## 1. Build
- [x] 1.1 `term.sh finished [--json]`: one verdict per open registry tab, read only; the issue check is shared with `close`
- [x] 1.2 Fake-backend tests for every verdict, must-pass and must-fail, and that `finished` sends no key and writes nothing
- [x] 1.3 The `orchestrate` skill: when `finished` runs, who reads an unsure tab, the standing approval that allows closing unasked
- [ ] 1.4 Real-tab check on throwaway tabs: `finished` on a finished worker, on one with a draft and on one with an open dialog, then `close` on the closable one
