## 1. Build
- [x] 1.1 Text survey and freeze use the live test for a tty's registry entry (HOME-460); fake-backend tests for a reused tty
- [x] 1.2 `term.sh reconcile` with two signals and no write on silence (HOME-461, HOME-462, HOME-467); tests in both directions
- [x] 1.3 `term.sh adopt <tty>|--all` (HOME-463, HOME-468, HOME-153); tests for skips, the caller, a lost session running again
- [x] 1.4 `term.sh reopen` (HOME-464, HOME-465, HOME-469): group windows and order, messages, skips, a failed open, memory, the worker cap
- [x] 1.5 `term.sh regroup` prints the plan and moves nothing (HOME-466)
- [x] 1.7 After review: alive needs tab and process (HOME-461), adopt follows a hand resume (HOME-470), forget (HOME-471), reopen checks the issue (HOME-472), one reopen at a time (HOME-473), profile and model come back (HOME-474), a Codex tab in the text survey (HOME-460); fake-backend tests in both directions
- [ ] 1.6 Real-tab check on throwaway tabs: open three test tabs in two groups, end their processes and tabs by hand, `reconcile`, `reopen --lost --dry-run`, `reopen --lost` (right windows, right messages, a running one skipped), `adopt` on a hand-opened tab; check that the real `be_tabs` (now exit 1 when the terminal cannot be read) still lists every tab, and that a window iTerm2 restores after a restart with the same tab ids and fresh shells has its entries marked lost; until it passes, reopen and adopt run only on the owner's word
