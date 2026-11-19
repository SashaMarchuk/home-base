## ADDED Requirements

### Requirement: HOME-449 An interview asks only the task's open questions
Interview mode SHALL make its package (questions, a short context page, a prompt) with the plugin or skill named in `voice.interview_plugin` when that key is set and the plugin is installed, never copying it into the home, and otherwise SHALL write the same three files by hand under the same rules, SHALL take every question from the task's open items and decisions and invent none, and SHALL quote the owner's words, never recap or reformulate them, in the prompt and in the answers file.

#### Scenario: A task with two open decisions
- **WHEN** a task's issue holds two open decisions and the owner asks for a voice interview on it
- **THEN** the package asks those two and no other question

#### Scenario: Answers are written back
- **WHEN** the answers file is written from the transcript
- **THEN** each answer is the owner's words as spoken, matched to its question

### Requirement: HOME-450 A voice transcript from the rollout
`scripts/voice-collect` SHALL read only the `realtime_item` lines of type `transcript_segment` of a Codex rollout, in their ordinal order, and print one timestamped turn per run of neighbouring segments of one speaker, joined as written, labelled "Me" for the user and "AI" for the assistant, text verbatim, dropping only an AI segment that is only a backchannel (a default English list, replaced by `voice.backchannels` when set).

#### Scenario: A backchannel and a short answer
- **WHEN** the AI says only "Mm-hm." and the user says only "Yes."
- **THEN** the AI segment is dropped and the user's "Yes." is kept as a turn

#### Scenario: A home's own backchannels
- **WHEN** `voice.backchannels=si,da` is set and the AI says only "Si." and later only "Mm-hm."
- **THEN** the "Si." segment is dropped and the "Mm-hm." segment is kept

#### Scenario: A word split across segments
- **WHEN** two neighbouring AI segments split one word
- **THEN** the turn holds the word whole

#### Scenario: The newest voice chat
- **WHEN** it runs with `--latest --since <time>`
- **THEN** it reads the newest rollout under the Codex sessions folder that holds a segment at or after that time, and exits 4 when none does

### Requirement: HOME-451 A transcript stays out of git
`scripts/voice-collect` SHALL write to standard output unless `--out` is given, and SHALL refuse with exit 3, writing nothing, an `--out` path inside a git work tree that git tracks (even when an ignore pattern matches it) or does not ignore.

#### Scenario: A path in the wiki
- **WHEN** `--out` names a file under the home's `wiki/`
- **THEN** it exits 3 and no file is written

#### Scenario: A tracked file under an ignored folder
- **WHEN** `--out` names a file under `.local/` that was added to git with `git add -f`
- **THEN** it exits 3 and the file is unchanged

#### Scenario: An ignored folder
- **WHEN** `--out` names a file under the home's gitignored `.local/`
- **THEN** the transcript is written there
