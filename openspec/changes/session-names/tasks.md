## 1. Build
- [x] 1.1 `launch_tab` adds `--name <name>` after the session id for every Claude Code launch (open, resume, thaw, reopen); the recorded resume line holds no name
- [x] 1.2 `open --name TEXT` (one line, not empty) is recorded and used again on resume, thaw and reopen; adopted tabs and other roles get no name
- [x] 1.3 `term.role.<role>.window` from `.local/config` only; a value that is not a plain name is ignored with a note
- [x] 1.4 open, resume, thaw and reopen place by the role window; the group stays; survey `place`; regroup plans by place
- [x] 1.5 Fake-backend tests: orchestrator and worker names, `--name`, resume, an adopted tab, the role window with and without `term.groups`, a worker beside it, a bad value, the key in `home.config`, reopen
- [x] 1.6 Real check: `claude --name` on a new and a resumed session (the name is stored), and the iTerm2 tab title of a throwaway tab shows the name
