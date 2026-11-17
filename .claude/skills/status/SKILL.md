---
name: status
description: Short, plain status of this home and its child homes. Use when the owner asks "status", "what's going on", "what needs me", "what's running", "what can I close", "what is frozen", or at the start of orchestration.
---

# status

Read only: the status itself writes nothing, and no tool beyond `gh` reads and the files of this home. The request's own issue (rule 1) is opened and finished by the orchestrator around it, not by this skill.

1. Repos: this home (`repo` in `home.config`) plus every `homes.<name>.repo` whose `role` is `child`.
2. Owner label per repo: this home's `labels.needs_owner`; for a child, read `labels.needs_owner` from `<homes.<name>.path>/home.config` (fall back to `gh api repos/<child>/contents/home.config` and decode; then to `needs-owner`). Read `.local/config` overrides only for this home.
3. One read per repo, open issues:
   `gh api "repos/<repo>/issues?state=open&per_page=100" --jq '.[] | select(.pull_request|not) | [.number, .title, ([.labels[].name]|join(","))] | @tsv'`
   (or one `gh api -X GET search/issues -f q='is:open is:issue repo:<a> repo:<b>'` across all of them).
   Plus, per repo, one read for an open Dreams PR: `gh api "repos/<repo>/issues?state=open&labels=dreams" --jq '.[] | select(.pull_request) | [.number, .title] | @tsv'`.
4. Skip issues labelled `dreams` (an open PR labelled `dreams` goes under **Needs you**: its proposals wait for the owner's review). Group, in this order, one line per issue (`<repo short>#<n> <title>`, plus why when it needs the owner):
   - **Needs you**: owner label set. Say the question in plain words.
   - **Only you can do**: `status:blocked` whose reason is an owner action (pay, sign in, approve).
   - **Running**: `status:claimed`.
   - **Frozen**: open issues whose title starts with `Freeze ` (one per freeze of sessions). One line each: how many sessions it holds and how many of them hold an open question of the owner (the rows of its table whose open question is not `-`). Not listed again under Parked.
   - **Parked**: `status:parked`.
   - **Can close**: `status:review`, and `needs-summary`.
   - **Ready**: count of `status:ready`; **Inbox**: count of `status:inbox`.
5. Add the session-start `SWEEP` lines that matter (stale claims, base ahead) as plain sentences.
6. Output: plain text, short, readable aloud. No tables, no links unless asked, empty groups left out. End with the one thing the owner should do first.
