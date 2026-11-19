## Why
The owner answers open questions by voice in a Codex voice chat. Two things went wrong before: questions were made up instead of taken from the task, and the owner's words were retold instead of quoted. The transcript itself sits in the Codex rollout file, mixed with every other event of the session, and had to be pulled out by hand.

## What Changes
- New HOME-449: interview mode makes its package with the plugin named in `voice.interview_plugin` when it is set and installed, never copied into the home, and otherwise writes the three files by hand; its questions come only from the task's open items and decisions, and neither the prompt nor the answers file recaps or reformulates the owner's words.
- New HOME-450: `scripts/voice-collect <rollout.jsonl> | --latest [--since <ISO>] [--out <file>]` writes a markdown transcript from the rollout's realtime `transcript_segment` items only: timestamped turns in segment order, "Me" and "AI", verbatim with speech-recognition errors kept, neighbouring segments of one speaker joined as written, and only AI segments that are a pure backchannel dropped (a default English list, replaced by `voice.backchannels` when a home sets it).
- New HOME-451: the transcript is raw data: standard output by default, and an `--out` path inside a git work tree that git does not ignore is refused.

## Impact
- New `scripts/voice-collect` (python3), a synthetic fixture `scripts/tests/fixtures/voice-rollout.jsonl`, tests (group `voice`), the `orchestrate` skill (section 9), the `voice.*` keys in `templates/home.config` and `scripts/configure`, the `CLAUDE.md` scripts row, README.
