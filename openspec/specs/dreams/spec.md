# dreams Specification

## Purpose
Dreams reviews past sessions for rules, corrections and contradictions the home missed and offers fixes as one pull request. It reads and suggests; it never applies, and merging the pull request is the owner's yes.

## Requirements

### Requirement: HOME-043 Standing Dreams issue
Each Dreams run SHALL record itself on one open issue labelled `dreams`, which is created once when absent, carries no status label, is skipped by the queue, the status report and the closed-issue sweep, and stays open after each run's final comment.

#### Scenario: First run
- **WHEN** no open issue labelled `dreams` exists
- **THEN** one is created with the label `dreams` and no `status:` label

#### Scenario: Run comment
- **WHEN** a run read something
- **THEN** it writes one final comment with `read-until: <UTC ISO>`, `result: <PR link | no findings>` and `facts: <shown>/<saved>` and the issue stays open

### Requirement: HOME-044 Watermark and input
A Dreams run SHALL read only input newer than the newest `read-until` line, or newer than `dreams.first_window_days` (default 14) days on the first run, taking local transcripts under `transcripts.paths` except sessions whose working directory starts with a `transcripts.exclude` prefix, else the comments of issues closed since the watermark.

#### Scenario: Nothing new
- **WHEN** no input is newer than the watermark
- **THEN** the run stops and writes nothing

### Requirement: HOME-045 Findings arrive as one pull request
Dreams SHALL put its findings into one pull request labelled `dreams` on a branch, updating the open one when it exists, editing existing pages in place, and never committing to `main`.

#### Scenario: Finding format
- **WHEN** a finding is recorded
- **THEN** it carries a one-line reason and the session id and no transcript text

### Requirement: HOME-046 Personal facts stay out of git
Dreams SHALL never put a personal fact into a pull request, issue or commit, stating only their count, and offer facts to the `facts.sink` only in an attended local run, saving each one only on the owner's yes.

#### Scenario: Unattended run
- **WHEN** a Dreams run is unattended or in the cloud
- **THEN** personal facts are skipped

### Requirement: HOME-047 Daily reminder
With `dreams.mode=daily`, the session-start hook SHALL print `dreams: due` when the standing Dreams issue is missing or was last updated more than 24 hours ago.

#### Scenario: Manual mode
- **WHEN** `dreams.mode` is `manual`
- **THEN** no reminder is printed
