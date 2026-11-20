## 1. Build
- [x] 1.1 `term.sh finished [--json]`: one verdict per open registry tab, read only; the issue check is shared with `close`
- [x] 1.2 Fake-backend tests for every verdict, must-pass and must-fail, and that `finished` sends no key and writes nothing
- [x] 1.3 The `orchestrate` skill: when `finished` runs, who reads an unsure tab, the home setting `term.close_finished` that allows closing unasked
- [ ] 1.4 Real-tab check on throwaway tabs: `finished` on a finished worker, on one with a draft and on one with an open dialog, then `close` on the closable one; also a tab whose session ended on its own (what the processes on its tty and the last screen line look like with the owner's prompt, so the lone-shell check of HOME-421 neither types into another program nor leaves every tab open), and a second worker on an issue the first one finished
- [x] 1.5 After review: only the tab's own run finishes it (HOME-061, HOME-415), adopted tabs are kept (HOME-420), moved and starting tabs are kept (HOME-419), `exit` goes only into a lone shell (HOME-421); fake-backend tests in both directions
