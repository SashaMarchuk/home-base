## Why
Tabs of workers that finished stay open until the owner asks to close them. The owner wants the orchestrator to close them on its own, cheaply: mechanical checks first, a small model for what the checks cannot read, a mid model for what the small one leaves unclear.

`term.sh close` already refuses every tab it cannot prove finished. What is missing is a way to see, without touching anything, which tabs `close` would accept, and a rule for when the orchestrator may call it unasked.

## What Changes
- New HOME-414, HOME-415, HOME-418 and HOME-419: `term.sh finished [--json]` lists every open tab of this home's registry with one verdict from the checks `close` runs: `closable`, `keep:<reason>` or `unsure:<what could not be read>`. It sends no key, writes nothing and closes nothing.
- HOME-061 and HOME-415: only the final comment of the run of the session in that tab counts (a worker's run id is its session id), so a follow-up worker on an issue an earlier run finished is kept, by `finished` and by `close`; the owner's own tab (`--adopt`) and an orchestrator tab, whose issue its workers finish, keep the any-run check in `close`; for such an orchestrator tab `finished` says `unsure:other-run` (HOME-418), never `closable`.
- New HOME-416 and HOME-417: the orchestrator runs `finished` after a worker's final record and at every status. `closable` tabs are closed with `term.sh close`, which checks everything again. An `unsure` tab's screen is read by a subagent on the `haiku` alias, and when that is unsure too, once by a subagent on the `sonnet` alias; a model's answer can only keep the tab open or allow calling `close`, never add a flag or close what `close` refuses. Anything still unsure stays open and is listed in the status.
- New HOME-420: a tab recorded with `--adopt` (the owner's own, every Codex tab included) is never `closable` (`keep:owner-tab`), and `close` needs `--adopt` on it every time.
- HOME-419: a tab is also kept when its session moved to another id (`keep:moved`), when its launch is not over (`keep:starting`) and when its session is gone but the tab is not a lone shell at an empty prompt (`keep:shell`).
- New HOME-421: `exit` is typed only into a lone shell; `close` of a session that was already gone also needs an empty prompt, and refuses a tab still starting. A prompt that ends in another character than `$`, `%`, `#` or `>` is not proven empty, so such a tab stays open.
- HOME-320 and HOME-416: closing `closable` tabs without asking needs the home's setting `term.close_finished=auto` (`home.config`, default `ask`); with `ask` the orchestrator lists them and closes on the owner's word, as before. Tabs outside the registry are closed only when the owner named them.

## Impact
- `scripts/term/term.sh` (the `finished` verb; the issue check of `close` becomes a function both use), tests on the fake backend for every verdict, the `orchestrate` skill (sections 1, 3 and 6), the README tool table.
- No new config key: the model aliases are named in the skill.
