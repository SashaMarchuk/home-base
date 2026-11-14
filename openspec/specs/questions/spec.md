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

### Requirement: HOME-080 A question is asked, never only written
A session SHALL ask the owner only through the ask tool, or with the owner away park its run with the question on the issue (`home-log checkpoint <n> --park --question <text>`), and SHALL never leave a question only in its final message.

#### Scenario: The owner is away
- **WHEN** a session needs the owner's decision and the owner is not present
- **THEN** it runs `home-log checkpoint <n> --park --question <text>` and stops waiting

#### Scenario: A free and reversible choice
- **WHEN** the recommended option is free and reversible
- **THEN** the session takes it, says so, and asks nothing

### Requirement: HOME-081 Every request gets an issue and a short report
A session SHALL open an issue in the home that owns it for every owner request before working on it, even when the session does the work itself and the answer is one line, and SHALL end with a report of at most five plain lines: done, waiting for the owner, next.

#### Scenario: A one-line answer
- **WHEN** the owner asks a question whose answer is one line
- **THEN** an issue is opened in the home that owns it before the answer, and the session reports on it in at most five lines

### Requirement: HOME-104 One decision per question, in the owner's language
Each question to the owner SHALL carry one decision, and every message to the owner, the final one included, SHALL be in the owner's language from `lang.owner`.

#### Scenario: Two decisions are pending
- **WHEN** a session needs the owner's approval of a text and a choice of where to post it
- **THEN** it asks two separate questions in the owner's language

### Requirement: HOME-105 Try the tools before handing a step to the owner
Before asking the owner to do a step, a session SHALL try every tool it has for that step once and do the read-only part itself, and SHALL not report a tool as blocked without having run it.

#### Scenario: A launch fails
- **WHEN** opening a worker for a task fails
- **THEN** the session does the read-only part of the task itself or in a subagent, and asks the owner only for what needs the owner

### Requirement: HOME-125 Run the check before a hand-off
Before handing a step to the owner, a session SHALL run the check that proves what is left, such as an identity call or a status command, and hand over only what that check shows is left.

#### Scenario: A login step
- **WHEN** a task needs a cloud login from the owner
- **THEN** the session runs the identity call first and asks for the login only when the call fails

### Requirement: HOME-126 Relay only on the owner's request
A session SHALL relay the owner's words into another session only when the owner asked for that relay, and only the owner's exact words.

#### Scenario: The owner asked for a draft only
- **WHEN** the owner asks for a draft only and a recorded answer of the owner's fits a waiting dialog
- **THEN** nothing is relayed into that dialog

#### Scenario: The owner asked for a relay
- **WHEN** the owner asks to pass the owner's answer to a session
- **THEN** the owner's exact words are typed, with nothing added

### Requirement: HOME-134 No issue closes over an open question
Before closing an issue, the orchestrator SHALL answer or store with `home-log checkpoint <n> --park --question` every open question of the owner on it.

#### Scenario: Resumed sessions stopped at questions
- **WHEN** the orchestrator is about to close an issue while sessions on it still wait on questions of the owner
- **THEN** each of those questions is answered or stored on the issue first

### Requirement: HOME-136 Many approvals go on one review page
When a session needs several yes/no approvals at once, it SHALL put them on one review page with an answer per row instead of a chain of questions.

#### Scenario: Five drafts wait for approval
- **WHEN** five reply drafts need the owner's yes or no
- **THEN** they are shown together on one page with an answer per row
