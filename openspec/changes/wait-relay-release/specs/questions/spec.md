## MODIFIED Requirements

### Requirement: HOME-126 Relay only on the owner's request
A session SHALL relay the owner's words into another session's waiting dialog only when the owner asked for that relay, and only the owner's exact words; outside a dialog, the orchestrator writes to a session only under HOME-446.

#### Scenario: The owner asked for a draft only
- **WHEN** the owner asks for a draft only and a recorded answer of the owner's fits a waiting dialog
- **THEN** nothing is relayed into that dialog

#### Scenario: The owner asked for a relay
- **WHEN** the owner asks to pass the owner's answer to a session
- **THEN** the owner's exact words are typed, with nothing added

## ADDED Requirements

### Requirement: HOME-445 Waiting on the owner's action
A session waiting on an action only the owner can do SHALL ask for it once through the ask tool, re-run the check that proves it done after 1, 5 and 15 minutes by itself, go on when a check passes, and after the 15-minute check fails ask through the ask tool whether it is done, or with the owner away park with that question; every worker brief SHALL carry this rule.

#### Scenario: The owner signs in after three minutes
- **WHEN** a worker asked the owner to sign in and the sign-in is done three minutes later
- **THEN** the 5-minute check passes and the worker goes on without asking again

#### Scenario: Nothing happens
- **WHEN** the 1, 5 and 15 minute checks all fail
- **THEN** the session asks through the ask tool whether the step is done

### Requirement: HOME-446 Writing to a session needs a reason
The orchestrator SHALL write to another session only when the owner closed something or gave context elsewhere (another session, a call, an issue) that settles or changes that session's question or work, and SHALL then send only that new context with its source, never a generic nudge and never an instruction of its own; "look at issue #n" (HOME-018), a dialog relay (HOME-107) and the message of `term.sh resume` (HOME-122) stay.

#### Scenario: A quiet worker
- **WHEN** a worker has been quiet for an hour and nothing new came from the owner
- **THEN** the orchestrator sends it nothing

#### Scenario: The owner settles a question elsewhere
- **WHEN** the owner, in the orchestrator's session, answers a question that another home's issue holds
- **THEN** the owner's words and the issue link are sent to that home's live orchestrator session, or to a new one opened with them in its brief, and nothing is written on that issue
