## MODIFIED Requirements

### Requirement: HOME-080 A question is asked, never only written
A session SHALL ask the owner only through the ask tool, or with the owner away park its run with the question on the issue (`home-log checkpoint <n> --park --question <text>`), except a worker, which with the owner away takes the reversible default and stores the question with `home-log checkpoint <n> --question <text>` without parking (HOME-148); no session SHALL leave a question only in its final message.

#### Scenario: The owner is away
- **WHEN** a session needs the owner's decision and the owner is not present
- **THEN** it runs `home-log checkpoint <n> --park --question <text>` and stops waiting

#### Scenario: A worker with the owner away
- **WHEN** a worker meets a choice for the owner while the owner is not present and a reversible default exists
- **THEN** it runs `home-log checkpoint <n> --question <text>` without `--park`, takes the default and keeps going

#### Scenario: A free and reversible choice
- **WHEN** the recommended option is free and reversible
- **THEN** the session takes it, says so, and asks nothing
