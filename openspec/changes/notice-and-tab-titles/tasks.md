## 1. Build
- [x] 1.1 `state_of` no longer reports `headsup`; `send`, `close`, `park` and both freeze loops no longer press 0; `finished` no longer returns `unsure:notice`
- [x] 1.2 `submit` puts one leading space before a text that starts with a digit while a notice shows
- [x] 1.3 `be_titles` (real and fake), `tab_title` and `title` in `survey --json`
- [x] 1.4 `regroup` plans a tab out of a window shared with another group or place that stays there
- [x] 1.5 Fake-backend tests: notice with an empty box, a draft, a running turn and a dialog for `send` and `state`; texts that start with 0, 1 and 2; a must-fail fixture (a bare digit goes to the notice); `close`, `park`, `finished` and `freeze --hard` with a notice; titles with a glyph, a spinner, no glyph, a plain title; regroup with a shared window and with a shell tab
- [x] 1.6 Real check: the screen shape of a live notice (notice above the box, the box reads empty) and `claude --name` keeping the title after a turn
