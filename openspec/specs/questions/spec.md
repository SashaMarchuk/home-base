# questions Specification

## Purpose
Anything that needs the owner is asked in exactly one place: the terminal when the owner is present, the issue when not. Answered questions are never asked again, and the owner's decisions are kept verbatim in an append-only file.

## Requirements

### Requirement: HOME-016 How the owner is asked
A question to the owner SHALL go through the surface's ask tool with context first, the recommended option first, and at most four questions per round.

#### Scenario: Several open points
- **WHEN** six points need the owner
- **THEN** at most four are asked in the first round, each with its recommended option first

### Requirement: HOME-017 A question waits on the issue when the owner is away
`home-log checkpoint <n> --question <text>` SHALL write the question into the run's comment as `Open question for the owner` and add the owner label, while `--clear-question` removes both.

#### Scenario: Owner away
- **WHEN** a worker cannot proceed without the owner and the owner is not present
- **THEN** the issue carries the owner label and the run's comment shows the open question

### Requirement: HOME-018 Answered questions are relayed
The orchestrator SHALL treat an issue with the owner label whose newest comment has no home-log marker as answered, relay it to the owning session with the text "look at issue #n" and nothing else, or run the task, and then remove the owner label.

#### Scenario: Answer on the phone
- **WHEN** the owner answers in an issue comment
- **THEN** the owning session is told to look at the issue and the owner label is removed

### Requirement: HOME-019 Open questions at session start
The session-start hook SHALL list the open issues carrying the owner label in this home and, using each child home's own owner label, in every child home.

#### Scenario: Child home has a question
- **WHEN** a child home has an open issue with its owner label
- **THEN** the session-start report lists it under that child's name

### Requirement: HOME-020 Never ask what is answered
Before asking the owner, a session SHALL search `DECISIONS.md`, the issue and earlier answers, and after a resume re-ask an open question once without ever answering it itself.

#### Scenario: Decision already recorded
- **WHEN** `DECISIONS.md` already settles the point
- **THEN** the owner is not asked

### Requirement: HOME-021 Decisions are recorded verbatim and append-only
The `decide` skill SHALL append each owner decision to `DECISIONS.md` as `### D-NNN` with the next free id, the verbatim quote, an English gloss when the quote is not in English, the source, supersedes, status and kind, and change an older entry only by setting its status line to `superseded-by D-NNN`.

#### Scenario: Decision replaces an older one
- **WHEN** the owner reverses decision D-004
- **THEN** a new entry is appended and only D-004's status line changes

#### Scenario: A default is not a decision
- **WHEN** a session picks a default the owner did not choose
- **THEN** nothing is appended and the point goes to an owner issue instead
