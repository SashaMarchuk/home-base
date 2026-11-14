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

#### Scenario: A standing approval covers the action
- **WHEN** the action is inside the scope of an active entry in the home section's Standing approvals and its conditions are met
- **THEN** the session does it without asking and writes `done under <ID>` in the finish text

#### Scenario: Outside a standing approval
- **WHEN** the action is outside every active entry's scope, or a condition of the entry is unmet
- **THEN** the session asks

### Requirement: HOME-021 Decisions are recorded verbatim and append-only
The `decide` skill SHALL append each owner decision to `DECISIONS.md` in the file's own entry format, by default `### <ID> — <title>` followed by plain `Quote:`, `Gloss:` (when the quote is not in English), `Source:`, `Status:` and `Kind:` lines (and an optional `Supersedes:` line), with the next id in the file's own id family (the owner is asked which family when the file mixes several), and change an older entry only by setting its `Status:` line to `superseded-by <ID>`.

#### Scenario: Decision replaces an older one
- **WHEN** the owner reverses decision D4
- **THEN** a new entry is appended and only D4's `Status:` line changes

#### Scenario: Next id continues the file's family
- **WHEN** the last entry of `DECISIONS.md` is `### D23 — ...`
- **THEN** the new entry is `### D24 — ...`, and no `D-001` series is started

#### Scenario: Another family
- **WHEN** the file numbers its entries `X-D001`, `X-D002`, ...
- **THEN** the new entry continues that family with the same zero-padding

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

### Requirement: HOME-141 An approved text is sent as approved
After the owner's yes on the exact text of a message or post, the session SHALL send it itself as approved and read it back.

#### Scenario: The owner approves a reply draft
- **WHEN** the owner says yes to the exact text of a reply
- **THEN** the session sends that text unchanged and reads the sent message back

### Requirement: HOME-151 The owner's own text in answer to a send question is the owner's yes
When the owner, in direct answer to a question asking whether to send a specific text, writes the text, the session SHALL treat that as the owner's yes on exactly that text: send it as written, read it back and not ask again.

#### Scenario: The owner rewrites the draft in the answer
- **WHEN** the session asks whether to send a draft and the owner answers with a replacement text the owner wrote
- **THEN** the session sends the replacement text as written, reads it back and asks no second send question

### Requirement: HOME-142 A draft with choices goes on one review page
When a draft comes together with other choices for the owner, the session SHALL show them on one review page with the draft as an editable text and yes / no / note per row, plus one pointer question.

#### Scenario: A draft and two options
- **WHEN** a reply draft and two choices wait for the owner
- **THEN** one review page holds the editable draft and a yes / no / note row for each, and one question points to it

### Requirement: HOME-152 A worker shows a draft on a review page
Every worker brief SHALL tell the worker to show a draft for the owner's approval on a review page, with the draft as an editable text and yes / no / note per row, not as a plain question.

#### Scenario: A worker prepares a reply
- **WHEN** a worker has a reply draft that needs the owner's approval
- **THEN** it shows the draft on a review page with an editable text and a yes / no / note row

### Requirement: HOME-188 A worker brief carries the standing approvals of its task
Every worker brief SHALL carry, in its `Rules:` block, one line with the id for each active standing approval in the home section's `Standing approvals` list that touches the task.

#### Scenario: A standing approval touches the task
- **WHEN** the home section lists an active standing approval whose scope covers the task
- **THEN** the brief's `Rules:` block has one line naming its id, action, scope and conditions

### Requirement: HOME-143 No confirmation of the owner's own order
The orchestrator SHALL report an order, plan or launch the owner gave instead of asking the owner to confirm it.

#### Scenario: The owner gave the launch order
- **WHEN** the owner names the order in which tasks start
- **THEN** the orchestrator starts them in that order and asks nothing about the order

### Requirement: HOME-144 Another tab's dialog is reported, not asked about
The orchestrator SHALL list in its status a waiting dialog in another tab that the owner did not ask to relay into, and never put it to the owner as a question.

#### Scenario: A tab waits on a dialog
- **WHEN** another tab waits on a dialog and the owner asked for no relay
- **THEN** the status names that tab's dialog and no question about it is asked

### Requirement: HOME-145 An explanation answers only what was asked
When the owner asks for an explanation, the final message SHALL answer only that, at the length the owner asked for, with no next step or proposal.

#### Scenario: A short explanation is asked for
- **WHEN** the owner asks briefly why something failed
- **THEN** the reply is a short plain explanation and ends without a proposal

### Requirement: HOME-148 Owner away: the worker asks nothing
Every worker brief SHALL tell the worker that, when the owner is away, it asks nothing, takes the reversible default and stores the question with `home-log checkpoint <n> --question`.

#### Scenario: A night run
- **WHEN** a worker meets a choice for the owner while the owner is away
- **THEN** it takes the reversible default and the question is stored on its issue

### Requirement: HOME-149 Owner away: waiting steps are stored before the final
When the owner is away, the orchestrator SHALL store every decision or step that waits for the owner before its final message: its own with `home-log checkpoint <n> --park --question` on an issue it holds, and one a worker will hit in that worker's brief.

#### Scenario: A night run ends with steps for the owner
- **WHEN** an unattended run ends with a decision only the owner can take
- **THEN** that decision is stored as a question on an issue, not only listed in the final message

### Requirement: HOME-158 An investigation ends with its finding
When the owner asked only to investigate or explain, the session SHALL put the finding and the fix it needs in the final status and finish the issue, never putting a fix the owner did not ask for to the owner as a question or parking the issue on one.

#### Scenario: A cause is found
- **WHEN** an investigation the owner asked for finds the cause and a possible fix
- **THEN** the final status names the cause and the fix, the issue is finished and no question about the fix is asked

### Requirement: HOME-159 A message to a tab carries only what is new
A message the orchestrator sends to another tab SHALL carry only what that tab does not have yet, read from its log or screen first, and no instruction the owner did not give.

#### Scenario: A tab already has a rule
- **WHEN** a tab's log shows it already received an owner rule
- **THEN** the next message to that tab does not repeat it and adds no instruction of its own

### Requirement: HOME-160 A draft is prepared, not offered
The session SHALL never ask the owner whether to prepare a draft; it SHALL prepare the draft and ask for the send with the exact text shown.

#### Scenario: A message is the next step
- **WHEN** the next step is a message that needs the owner's yes
- **THEN** the question that asks for the send shows the drafted text and no earlier question asks whether to draft it

### Requirement: HOME-161 Counts in a result add up
Counts in a result SHALL come from one source and add up to the total stated.

#### Scenario: Notices split by cause
- **WHEN** a result splits seven notices by cause
- **THEN** the parts add up to seven and come from the same source

### Requirement: HOME-162 A login request carries its command
A login request to the owner SHALL name the service, the profile by name and one pasteable `! <login command>` taken from the home's login how-to, in the question text, with options that never replace that command, and after the owner's confirmation the session SHALL run the identity check before anything else.

#### Scenario: A cloud login has expired
- **WHEN** an identity check fails on an expired login
- **THEN** the question names the service and profile and holds the pasteable login command, and the identity check runs right after the owner confirms

### Requirement: HOME-163 A re-check names its limits
After a re-check, the session SHALL name what the check cannot prove.

#### Scenario: An account is re-checked
- **WHEN** the session re-checks which account a profile uses
- **THEN** its report names what that check cannot prove

### Requirement: HOME-164 A standing rule inside a request is recorded
A standing rule the owner states inside another request SHALL be recorded with the `decide` skill in that task.

#### Scenario: A rule in passing
- **WHEN** the owner states a rule for all future cases while asking for something else
- **THEN** that task appends the rule to `DECISIONS.md` through the `decide` skill

#### Scenario: A standing approval
- **WHEN** the owner says an action needs no confirm from now on
- **THEN** the entry carries `Standing: yes` with `Allows:`, `Where:`, `Unless:` and `Until:` lines in the scope the owner named, and the home section of `CLAUDE.md` gets one line for it under `### Standing approvals`

#### Scenario: A standing approval is withdrawn
- **WHEN** the owner withdraws a standing approval
- **THEN** a new entry with the owner's words supersedes it, only the old entry's `Status:` line changes, its `Standing approvals` line is removed, and no commit is reverted

#### Scenario: The owner says no to an action done under a standing approval
- **WHEN** the owner says no to, edits or undoes an action done under a standing entry
- **THEN** the session stops using that entry for this task only, records the owner's words as a plain entry, and the standing entry stays active until the owner withdraws it

### Requirement: HOME-165 A yes to the pointer question approves the page as shown
The first option of a pointer question SHALL be a plain yes to everything as shown on the review page, in the owner's language; after the owner's yes the session reads the page, where a row the owner answered or text the owner edited wins, acts on it, reads it back and does not ask again.

#### Scenario: The owner says yes to the pointer question
- **WHEN** the owner picks the first option of a pointer question whose page holds a draft the owner did not edit
- **THEN** the session sends the draft as shown, reads it back and asks nothing more about it

### Requirement: HOME-166 A blocker report is its own question
A report that a step is blocked SHALL be its own question, asked before any draft for that step and never bundled with a draft's approval.

#### Scenario: A checkout is blocked
- **WHEN** a purchase step is blocked and a message to a third party could be drafted
- **THEN** the session first asks about the blocker alone, and any draft follows in a later question

### Requirement: HOME-169 A review page saves each answer and splits options
A review page SHALL save each answer as it is given, with no submit or Save button, and show each option in a finding as its own yes / no / note row.

#### Scenario: A finding offers two options
- **WHEN** a finding offers a custom page and a new block as options
- **THEN** the page shows two separate rows and keeps each answer the moment the owner gives it

### Requirement: HOME-170 Approved text keeps its words and takes the recipient's format
Approved text SHALL be sent with its words unchanged, in the format the recipient's recorded rules give.

#### Scenario: The recipient wants one point per message
- **WHEN** an approved three-paragraph reply goes to a recipient whose recorded rule is one point per message
- **THEN** it goes out as three messages with the approved words
