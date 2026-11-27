## Why
Two owner requests from 27.11, sent by the S&F home's orchestrator.

1. A "✦ Heads up · …" notice that a plugin shows above a session's input box (the line with "1: Learn more   2: Knew this already   0: Dismiss") is not a blocker and not a question. The owner may prompt while it shows; it may stay there for good; its hints may be useful. `term.sh send` refused twice on 27.11 ("the notice on ttysNNN did not go away after one dismiss; nothing sent") and `term.sh state` printed `headsup` instead of the state under it.
2. The owner wants every session of every home named and placed by one rule: all orchestrators in one window, other tabs grouped by type in their own windows, orchestrator titles that follow the rule, and the tab's name written next to every session id or tty a session names to him, so he can open it at once. He does not need a feature that explains which id is which.

Facts used (checked on a real machine, Claude Code 2.1):
- The notice is drawn above the top border of the input box; the box under it reads as usual. A digit typed into the empty box picks the notice's option of that number (0 dismisses it); once the box holds text, digits are typed as text.
- `claude --name <name>` keeps the terminal title through the first prompt and after the turn ends (checked in a detached terminal: the title stayed "✳ <name>").
- iTerm2's AppleScript gives each session's `name`: the title the owner sees, such as "✳ <name> (claude)" or, for a session started without a name, a summary of its first prompt.

## What Changes
- New HOME-489: a heads-up notice is never dismissed and never blocks. `state` reports the state under it (the word `headsup` is gone); `send`, `park`, `close` and `freeze` type into the empty box with it shown; `finished` judges the box under it (`unsure:notice` is gone). A text that starts with a digit gets one leading space while a notice shows, so the notice never takes that key. The base `CLAUDE.md` (rule 10) and the orchestrate skill say that orchestrators never ask the owner to dismiss it.
- New HOME-490: `survey --json` gives each tab its `title`, the tab title the owner sees, without the status glyph and the trailing " (claude)". It is for display only and never a target. A new base rule (19) and the orchestrate and status skills say: next to each session id or tty named to the owner, write the tab's title.
- New HOME-491: `regroup --dry-run` also plans a registered tab out of a window it shares with live sessions of another group or place that stay there (tabs this home did not open count by their folder's group); it moves such a tab to a new window (`-> new`). Before, a lone orchestrator inside a window of S&F tabs counted as in place.
- The orchestrate skill says how an orchestrator gets its name (`term.sh open <home> --role orchestrator`) and that the owner's group list by type lives in `.local/config`. The group list itself is the owner's and stays out of the base.

## Impact
- `scripts/term/term.sh` (rule 4, `state_of`, `send`, `close`, `park`, `finished`, `submit`, new `be_titles`), `scripts/term/freeze.sh` (`agree`, both freeze loops), `scripts/term/sessions.sh` (`tab_title`, survey `title`), `scripts/term/recover.sh` (`regroup`); the fake backend models the notice's digit keys and tab titles; tests must pass and must fail.
- `CLAUDE.md` base block: rule 10 gains one sentence, new rule 19. Orchestrate and status skills.
- No new dependency, no new key.
