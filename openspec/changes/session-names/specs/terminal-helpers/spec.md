## ADDED Requirements

### Requirement: HOME-487 A session starts under a clear name
`term.sh open`, `resume`, `thaw` and `reopen` SHALL start a Claude Code session with `--name <name>` placed right after its session id and before any brief or message (only when the recorded command ends with that `--session-id <id>` or `--resume <id>`; text inside a brief, a message or a quoted folder never moves the name), where the name is the registry entry's `name` (set by `open --name`; `thaw` takes it from the freeze snapshot when the registry has no entry), else `Orchestrator · <home>` for the orchestrator role (`<home>`: the repo name in the session folder's `home.config`, else the folder's name), else `<this home> #<issue>` for a worker with an issue, else `<this home> · <folder>`; they SHALL pass no name for an adopted tab or a session of any other role, SHALL keep the recorded resume line without the name, and SHALL never address a tab by its title.

#### Scenario: An orchestrator of a child home
- **WHEN** `term.sh open <child home> --role orchestrator` runs and the child's `home.config` says `repo=<owner>/child-home`
- **THEN** the session starts with `--name 'Orchestrator · child-home'` and its tab title shows that name

#### Scenario: A worker
- **WHEN** `term.sh open <dir> --issue 7` runs in the home `<owner>/home`
- **THEN** the session starts with `--name 'home #7'`

#### Scenario: A name given at open
- **WHEN** `term.sh open <dir> --issue 8 --name "home #8 fix the sweep"` runs and the session is later resumed
- **THEN** both launches carry that name; a name of two lines or an empty one exits 2 with nothing opened

#### Scenario: Text that repeats an option
- **WHEN** a brief says `Implement the --name option`, a resume message holds `--session-id <id>` or `--resume <id>`, or thawed freeze data holds a folder whose name holds `--resume <id>`
- **THEN** the name still comes right after the real option, outside every quote, and the brief, message and folder reach the session unchanged

#### Scenario: The owner's own tab
- **WHEN** an adopted tab is resumed
- **THEN** its launch line carries no name

### Requirement: HOME-488 A role may have a window of its own
With `term.role.<role>.window=<name>` in `.local/config` (never `home.config`), `term.sh open`, `resume`, `thaw` and `reopen` SHALL place a session of that role in the window of that name, found as a group's window is found, SHALL keep the tab's group (freeze record, thaw order, selectors) as it would be without the key, SHALL report the place in `survey --json` (`place`: that name, else the group), and SHALL ignore a value that is not a plain name.

#### Scenario: Orchestrators of several homes
- **WHEN** `term.role.orchestrator.window=Orchestrators` is set and orchestrators open from folders of two different groups
- **THEN** both open in the same window, created for the first one and cached under `Orchestrators`, and each keeps its own group

#### Scenario: A worker beside them
- **WHEN** a worker opens in a folder of a group whose orchestrator sits in the role window
- **THEN** the worker opens in its group's window, not in the role window

#### Scenario: The key in the committed file
- **WHEN** the key is in `home.config` only
- **THEN** placement is as without the key
