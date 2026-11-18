## Why
HOME-080 says a session with the owner away parks its run with the question. HOME-148 says a worker with the owner away asks nothing, takes the reversible default and stores the question without parking, so it can keep going. The two approved requirements disagree for a worker. The owner decided that this is a setting of each home.

## What Changes
- A new committed key, `questions.worker_away=park|continue`, default `park`; `.local/config` may override it like every key, and an unset key counts as `park`.
- HOME-080: with the owner away every session parks with its question; only a worker in a home set to `continue` takes the reversible default, stores the question with `home-log checkpoint <n> --question <text>` without `--park` and keeps going.
- HOME-148: the worker brief carries the owner-away line that the home's setting gives, written by the orchestrator when it writes the brief.

## Impact
- `openspec/specs/questions/spec.md`, rule 5 of `CLAUDE.md`, the worker brief in the `orchestrate` skill, `templates/home.config`, `templates/answers.example`, `scripts/configure` (the key as a default that is not asked, and its two values), tests.
- No change to `scripts/home-log`: `checkpoint --question` with and without `--park` exists already (HOME-017).
- A home whose `home.config` lacks the key gets `park`.
