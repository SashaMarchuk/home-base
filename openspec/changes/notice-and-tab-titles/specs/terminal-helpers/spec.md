## ADDED Requirements

### Requirement: HOME-489 A heads-up notice is not a blocker
A "Heads up" notice (a line holding "0: Dismiss") above a session's input box SHALL never be dismissed by the terminal helpers and SHALL never block them: `term.sh state` SHALL report the state under it, `send`, `park`, `close` and `freeze` SHALL type into the empty box with the notice shown, `finished` SHALL judge the box under it, and a text that starts with a digit SHALL get one leading space while a notice shows, so the notice never takes that digit as its choice.

#### Scenario: Send with a notice shown
- **WHEN** a tab shows a notice and an empty input box, and `term.sh send <tab> hello` runs
- **THEN** `hello` is submitted, no 0 is typed and the notice is still shown

#### Scenario: A text that starts with a digit
- **WHEN** a tab shows a notice and an empty box, and `term.sh send <tab> "0 of 3 done"` runs
- **THEN** the submitted line holds the whole text and no key reaches the notice

#### Scenario: State under the notice
- **WHEN** a tab shows a notice over an empty box, a draft or a running turn
- **THEN** `state` prints `idle`, `draft` or `busy`

#### Scenario: Close, park and freeze
- **WHEN** a finished session, a session to park or a session to freeze shows a notice
- **THEN** `close`, `park` and `freeze --hard` exit the session with no 0 typed

### Requirement: HOME-490 The tab title next to every id
`term.sh survey --json` SHALL give each live tab a `title`: the tab title the terminal shows, without a leading status glyph and a trailing process name in brackets, for display only and never accepted as a target.

#### Scenario: A named orchestrator
- **WHEN** iTerm2 shows a tab as "✳ Orchestrator · home (claude)"
- **THEN** its `title` is `Orchestrator · home`

#### Scenario: A session started without a name
- **WHEN** iTerm2 shows a tab as "Issue #71 via orchestrate skill (claude)"
- **THEN** its `title` is `Issue #71 via orchestrate skill`

### Requirement: HOME-491 A shared window is no group's window
`term.sh regroup --dry-run` SHALL plan a registered tab out of its group's window when that window also holds live sessions of another group or place that stay there (a tab this home did not open counts by its folder's group; a registered tab planned to leave and a plain shell do not count), with the target `new`.

#### Scenario: An orchestrator among S&F tabs
- **WHEN** a registered tab of the place `Orchestrators` is the only one of its place and shares its window with S&F tabs
- **THEN** the plan says `MOVE <tty> <id> group Orchestrators: window <w> -> new (window <w> also holds sf)`

## MODIFIED Requirements

### Requirement: HOME-057 Safe typing
`term.sh send` SHALL type one line only when the tab shows no dialog, no running turn and an empty input box (a heads-up notice above the box changes none of this, see HOME-489), treating text in the box as a suggestion only when a single probe character comes back alone, and pressing a swallowed Enter once more and never twice.

### Requirement: HOME-072 Reading a tab
`term.sh state` SHALL print one word for a target tab: `gone` when its recorded process has ended, exit 4 with no word when the tab itself is gone or its screen cannot be read, else the first that applies of an open dialog, a running turn, no input box (`shell`), background jobs, unsent text in the box and an empty box (`idle`), a heads-up notice not counting, while `term.sh screen` prints the tab's screen text, its last lines only with `--lines N`.

### Requirement: HOME-310 Two signals before a key
`term.sh freeze` SHALL send a key to a tab only while its session file's status and its screen agree: `idle` with an idle, draft or background-job screen (a heads-up notice above the box not counting), `busy` with a running turn, `waiting` with a dialog.
