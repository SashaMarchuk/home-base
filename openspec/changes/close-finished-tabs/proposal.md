## Why
Tabs of workers that finished stay open until the owner asks to close them. The owner wants the orchestrator to close them on its own, cheaply: mechanical checks first, a small model for what the checks cannot read, a mid model for what the small one leaves unclear.

`term.sh close` already refuses every tab it cannot prove finished. What is missing is a way to see, without touching anything, which tabs `close` would accept, and a rule for when the orchestrator may call it unasked.

## What Changes
- New HOME-414, HOME-415 and HOME-418: `term.sh finished [--json]` lists every open tab of this home's registry with one verdict from the checks `close` runs: `closable`, `keep:<reason>` or `unsure:<what could not be read>`. It sends no key, writes nothing and closes nothing.
- New HOME-416 and HOME-417: the orchestrator runs `finished` after a worker's final record and at every status. `closable` tabs are closed with `term.sh close`, which checks everything again. An `unsure` tab's screen is read by a subagent on the `haiku` alias, and when that is unsure too, once by a subagent on the `sonnet` alias; a model's answer can only keep the tab open or allow calling `close`, never add a flag or close what `close` refuses. Anything still unsure stays open and is listed in the status.
- HOME-320 and HOME-416: closing `closable` tabs without asking needs an active standing approval of the owner in `DECISIONS.md` (listed in the home section); without one the orchestrator lists them and closes on the owner's word, as before. Tabs outside the registry are closed only when the owner named them.

## Impact
- `scripts/term/term.sh` (the `finished` verb; the issue check of `close` becomes a function both use), tests on the fake backend for every verdict, the `orchestrate` skill (sections 1, 3 and 6), the README tool table.
- No new config key: the model aliases are named in the skill.
