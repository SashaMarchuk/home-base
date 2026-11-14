# proactivity Specification

## Purpose
How much a home acts without being told is one setting with three levels. At every level the home acts only while a session runs, never sends anything external on its own, and asks before heavy work.

## Requirements

### Requirement: HOME-030 Proactivity levels
The orchestrator SHALL follow `proactivity.mode`: `off` acts only on what the owner says in the session, `assigned` (the default) also works `status:ready` issues and prepares replies for the owner to pick, and `watch` also checks `proactivity.sources` every `proactivity.every_minutes` (default 60) with the session's own scheduler.

#### Scenario: Watch finds work
- **WHEN** a watched source shows new work in `watch` mode
- **THEN** it becomes an inbox issue through `home-log new` or goes to the session that owns it

#### Scenario: Off
- **WHEN** the mode is `off`
- **THEN** no ready issue is started unless the owner says so in the session

### Requirement: HOME-031 Nothing external without the owner's yes
A home SHALL send no message, post, invitation, purchase, production change or push to a repository other than its own without the owner's explicit yes, and instead prepare the text, the payment or the change for the owner to confirm or click.

#### Scenario: Reply to a message
- **WHEN** work needs a reply to someone outside the home
- **THEN** the reply is prepared and confirmed through the ask tool before anything is sent

#### Scenario: Push to another repository
- **WHEN** work would push to a repository that is not this home's own
- **THEN** the push waits for the owner's explicit yes, while this home's own commits and the base-update flow need none

### Requirement: HOME-032 Heavy work asks first
At every level, starting more than one helper session or reading in bulk SHALL wait for the owner's yes.

#### Scenario: Bulk reading
- **WHEN** a task would read a large set of transcripts
- **THEN** the owner is asked first

### Requirement: HOME-033 No background service
A home SHALL act only while one of its sessions runs, with no database, daemon or state file in git.

#### Scenario: No session open
- **WHEN** no session of the home is running
- **THEN** nothing in the home acts except its scheduled CI workflows

### Requirement: HOME-135 Leave it and watch
When the owner chooses to leave something and watch it, the orchestrator SHALL file a follow-up issue for the watch and then finish.

#### Scenario: The owner says leave it and watch
- **WHEN** the owner picks "leave it and watch"
- **THEN** a follow-up issue for the watch exists before the orchestrator's final comment
