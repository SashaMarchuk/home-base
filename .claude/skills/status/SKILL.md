---
name: status
description: Short, plain status of this home and its related homes in one view. Use when the owner asks "status", "what's going on", "what needs me", "what's running", "what can I close", "what is frozen", or at the start of orchestration.
---

# status

Read only: the status itself writes nothing, and uses no tool beyond `scripts/home-status`, `gh` reads and the files of the homes. The request's own issue (rule 1) is opened and finished by the orchestrator around it, not by this skill.

1. Run `scripts/home-status --all`: this home, then every related home whose role is `child` or `peer` (`homes.*` in `home.config`); add `--home <name>` for a parent the owner asks about. One block per home: its open issues by state (`question` lines carry that home's own owner label, read from its clone's `home.config`), then its sessions from that home's `.local/registry.json` (`live`, `lost`, `stopped?`, `starting`). It reads only, through each home's own `gh.config_dir`, and never switches an account. A line `issues: cannot read <repo>` is said as such, never as zero.
2. A task started in a related home is shown like one handed there: the owning home's issue is the only record. Read context from that home's issues and wiki by link; never copy it here.
3. Per repo, one read for an open Dreams PR: `gh api "repos/<repo>/issues?state=open&labels=dreams" --jq '.[] | select(.pull_request) | [.number, .title] | @tsv'`.
4. Issues labelled `dreams` are already skipped (an open PR labelled `dreams` goes under **Needs you**: its proposals wait for the owner's review). Group, in this order, one line per issue (`<home name>#<n> <title>`, plus why when it needs the owner):
   - **Needs you**: `question` lines. Say the question in plain words.
   - **Only you can do**: `blocked` whose reason is an owner action (pay, sign in, approve).
   - **Running**: `claimed`, with the home's `live` sessions, each named by its tab title (`title` in `scripts/term/term.sh survey --json`) next to any id; a `stopped?` session (its process gone, one signal only) is said once as "may have stopped", never as finished; a `lost` session (marked by `term.sh reconcile`: its tab and process are gone) is said as lost, with `term.sh reopen --lost --dry-run` as the way back.
   - **Frozen**: `frozen`, the open issues whose title starts with `Freeze ` (one per freeze of sessions). One line each, from that issue's body: how many sessions it holds and how many of them hold an open question of the owner (the rows of its table whose open question is not `-`). Not listed again under Parked.
   - **Parked**: `parked`.
   - **Can close**: `review` (`status:review` and `needs-summary`).
   - **Handed on (older)**: `delegated`, an older issue here whose work runs in another home; it closes when the sweep reports that issue closed.
   - **Ready**: count of `ready`; **Inbox**: count of `inbox`; **Other**: count of `open` (no status label).
5. Add the session-start `SWEEP` lines that matter (stale claims, base ahead) as plain sentences.
6. Output: plain text, short, readable aloud. No tables, no links unless asked, empty groups left out. End with the one thing the owner should do first.
