## MODIFIED Requirements

### Requirement: HOME-124 Issue first, at session start
The session-start hook SHALL print the line "Every request gets an issue first: first call scripts/home-log new --title T --body B --start (opens and claims it); last scripts/home-log finish <n> --text ..., a question or an explanation included. Work another home owns: its one issue goes there (new --repo <its repo> --ready), none here.", and the `orchestrate` and `task` skills SHALL open with that step.

#### Scenario: A short ask
- **WHEN** the owner asks for an explanation in a new session
- **THEN** the session has seen the issue-first line and opens an issue before it answers

#### Scenario: Another home's work
- **WHEN** a session starts in a home that names related homes
- **THEN** the issue-first line also says that another home's work gets its one issue in that home and none here
