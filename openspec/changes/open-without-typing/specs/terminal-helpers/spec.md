## ADDED Requirements

### Requirement: HOME-409 A new tab starts with its command
`term.sh open`, `resume` and `thaw` SHALL create the tab or window with the launch line as its command and send no key to it, the command being the caller's login shell (`$SHELL` when it is zsh, bash, ksh or sh by an absolute path, else `/bin/zsh`) started as a login and interactive shell that runs the launch line and then replaces itself with a login shell, and SHALL record as the session's process only a process on the new tty that runs the launch command by name.

#### Scenario: Keys typed elsewhere while a tab opens
- **WHEN** the owner types in another tab while `term.sh open` creates a tab
- **THEN** the session starts with exactly the launch line the helper built, because that line is never typed

#### Scenario: The session ends
- **WHEN** the session started by the command exits
- **THEN** the tab shows a login shell, and `close` ends that shell as before

#### Scenario: A shell around the session
- **WHEN** the shell that runs the launch line is on the new tty with a higher process id than the session
- **THEN** the registry records the session's process, not the shell

#### Scenario: The tab cannot be created
- **WHEN** creating the tab fails
- **THEN** the verb exits 4, the registry entry is marked closed and nothing is typed anywhere

### Requirement: HOME-410 The launch line reaches the shell unchanged
`term.sh` SHALL carry the launch line inside the tab's command as hex digits that the shell decodes and evaluates, so the command holds no character of the line itself, and SHALL exit 3 with nothing opened when the line cannot be encoded or the decoder is missing.

#### Scenario: Quotes in a folder name and a brief
- **WHEN** `term.sh open` runs for a folder whose name holds a single quote, with a brief holding single quotes, double quotes, a dollar sign and a backslash
- **THEN** the session receives that brief as one argument, unchanged, in that folder

#### Scenario: A command of another shape
- **WHEN** the backend is given a command that is not the login-shell wrapper
- **THEN** no tab is created

### Requirement: HOME-411 The focus stays where it was
After creating a tab or window, `term.sh` SHALL select again, in the same script, the tab that was shown in the target window and the tab, session and window that were in front before, and SHALL never activate the terminal app; it does not guarantee that no key reaches the new session's input box during the instant the new tab is in front, and such keys stay there as an unsent draft that `close`, `park` and `freeze` never erase.

#### Scenario: A tab opens in the front window
- **WHEN** `term.sh open` creates a tab in the window the owner is working in
- **THEN** the owner's tab is the selected tab of that window again when the helper returns

#### Scenario: Keys that reached the new session
- **WHEN** keys pressed during the creation landed in the new session's input box
- **THEN** they are an unsent draft there, and `close` on that tab exits 3 and keeps them

### Requirement: HOME-412 The recorded resume line names the real profile
When `launch.profile_flag` is set and `launch.profile.<role>` is not, `term.sh open` SHALL wait up to its open timeout for the new session's session file (HOME-301) and record the resume line with that file's profile, built as for an adopted tab (HOME-129), and SHALL keep the line without a profile when the file does not appear, names another session id or names no profile; no setting is added.

#### Scenario: The machine picked the profile
- **WHEN** `launch.profile_flag` is `-p`, no `launch.profile.worker` is set, and the new session's file is under the profile folder `work`
- **THEN** the registry's resume line is `cd <cwd> && 'claude' -p 'work' --resume <id>`

#### Scenario: No session file
- **WHEN** the session file does not appear within the open timeout
- **THEN** the resume line is recorded without a profile and `open` still prints the session
