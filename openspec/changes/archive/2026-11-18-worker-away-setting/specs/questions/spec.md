## MODIFIED Requirements

### Requirement: HOME-080 A question is asked, never only written
A session SHALL ask the owner only through the ask tool, or with the owner away park its run with the question on the issue (`home-log checkpoint <n> --park --question <text>`), and SHALL never leave a question only in its final message. Only a worker in a home whose `questions.worker_away` is `continue` SHALL, where a reversible default exists, take that default, store the question with `home-log checkpoint <n> --question <text>` without `--park` and keep going (HOME-148).

#### Scenario: The owner is away
- **WHEN** a session needs the owner's decision and the owner is not present
- **THEN** it runs `home-log checkpoint <n> --park --question <text>` and stops waiting

#### Scenario: A worker in a home set to park
- **WHEN** a worker meets a choice for the owner while the owner is not present and `questions.worker_away` is `park` or not set
- **THEN** it runs `home-log checkpoint <n> --park --question <text>` and stops waiting

#### Scenario: A worker in a home set to continue
- **WHEN** a worker meets a choice for the owner while the owner is not present, `questions.worker_away` is `continue` and a reversible default exists
- **THEN** it runs `home-log checkpoint <n> --question <text>` without `--park`, takes the default and keeps going

#### Scenario: A worker in a home set to continue without a reversible default
- **WHEN** a worker meets a choice for the owner while the owner is not present, `questions.worker_away` is `continue` and no option is reversible
- **THEN** it runs `home-log checkpoint <n> --park --question <text>` and stops waiting

#### Scenario: A free and reversible choice
- **WHEN** the recommended option is free and reversible
- **THEN** the session takes it, says so, and asks nothing

### Requirement: HOME-148 Owner away: the worker asks nothing
Every worker brief SHALL carry the owner-away line that the home's `questions.worker_away` gives, read by the orchestrator when it writes the brief: with `park` (the default, and the meaning of an unset key or any other value) the worker asks nothing and parks its run with the question (`home-log checkpoint <n> --park --question`); with `continue` it asks nothing, takes the reversible default and stores the question with `home-log checkpoint <n> --question`.

#### Scenario: A night run
- **WHEN** a worker in a home with `questions.worker_away=continue` meets a choice for the owner while the owner is away
- **THEN** it takes the reversible default and the question is stored on its issue

#### Scenario: A night run in a home set to park
- **WHEN** the orchestrator of a home with `questions.worker_away=park` writes a worker brief
- **THEN** the brief tells the worker to park its run with the question when the owner is away

#### Scenario: The key is not set
- **WHEN** neither `home.config` nor `.local/config` holds `questions.worker_away`
- **THEN** the brief carries the `park` line

#### Scenario: A new home
- **WHEN** `scripts/configure` writes a new home's `home.config` from answers that do not name the key
- **THEN** the file holds `questions.worker_away=park`, and no question about it is asked
