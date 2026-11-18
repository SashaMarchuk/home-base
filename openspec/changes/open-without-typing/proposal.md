## Why
`term.sh open` creates a tab and then types the launch line into it. The new tab takes the keyboard focus, so whatever the owner is typing elsewhere at that moment lands in the new tab and is mixed into the launch line; the session then starts with a broken command, or does not start. `resume` and `thaw` reopen sessions the same way.

A second gap: with `launch.profile_flag` set and no `launch.profile.<role>`, the machine picks the profile on its own (the launch command resolves it from the folder), and the resume line recorded at `open` names no profile, while a tab the owner opened by hand already gets its profile from its session file (HOME-129).

Facts used (iTerm2's scripting dictionary and source, read only):
- `create window with default profile command "<cmd>"` and `create tab with default profile command "<cmd>"` start the tab with that command instead of the profile's login shell; nothing is typed.
- iTerm2 splits the command into words itself, with its own quote and backslash rules (a backslash escapes even inside single quotes), not a shell's.
- `select` on a tab makes it the current tab of its window; on a session it does not change the tab or the window; on a window it brings the window to the front and gives it the keyboard focus. The dictionary does not say whether a window `select` activates the app.

## What Changes
- New HOME-409: `open`, `resume` and `thaw` pass the launch line as the new tab's command; no key is sent to the new tab. The command is the login shell, which loads the user's environment, runs the line and stays as a shell after the session ends, so `close`, `park` and `resume` work as before.
- New HOME-410: the launch line travels inside that command as hex digits, so no quote, backslash or space of a folder name or a brief meets the terminal's word splitting.
- New HOME-411: the tab, session and window that were in front before the new tab was created are selected again in the same script; the app is never activated. Not guaranteed: keys pressed during the instant the new tab is in front can land in the new session's input box (never in its launch line); the draft check then keeps that tab from being closed or parked.
- New HOME-412: with `launch.profile_flag` set and no `launch.profile.<role>`, the resume line recorded at `open` names the profile of the session's own session file; no new setting. When the session file does not appear or names no profile, the line is recorded without one, as before.
- The process recorded for a new tab is the one that runs the launch command by name, never the shell around it.

## Impact
- `scripts/term/term.sh` (`be_open`, `launch_tab`, `open`), the fake backend, tests on the fake backend (must-pass and must-fail), the AppleScript compile test.
- Needs `perl` (part of macOS, already used by the session-end hook) on the machine that opens tabs, to decode the line.
- No change to where sessions or transcripts are stored.
