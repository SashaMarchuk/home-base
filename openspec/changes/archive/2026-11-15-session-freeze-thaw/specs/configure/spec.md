## MODIFIED Requirements

### Requirement: HOME-137 One step changes a machine key
`scripts/configure --set <key>=<value>` SHALL change only `.local/config` and only the machine keys `launch.*`, `terminal_helpers`, `limits.reader`, `gh.config_dir`, `transcripts.*` and the session keys (HOME-323), check each value as an answer is checked, remove the key on an empty value, keep every other line, print `<key>=<effective value>`, and refuse with exit 2 and nothing written any other key or an invalid value; `--get <key>` prints the same line without writing.

#### Scenario: Worker profile set, then unset
- **WHEN** `scripts/configure --set launch.profile.worker=personal` runs twice, then `scripts/configure --set launch.profile.worker=` runs
- **THEN** after the first two runs `.local/config` holds one line `launch.profile.worker=personal` and prints it, and after the third that line is gone and `launch.profile.worker=` is printed

#### Scenario: Committed key refused
- **WHEN** `scripts/configure --set repo=example-org/other` runs
- **THEN** it exits 2 naming `repo` as a committed key, and neither `home.config` nor `.local/config` changes

## ADDED Requirements

### Requirement: HOME-323 Values of the session keys
`scripts/configure --set` SHALL accept `term.sessions_dirs` and `term.group.<name>.cwd` as folders starting with `/` or `~/`, `term.groups` as lower-case names, `term.group.<name>.home` as `self` or a name of `homes.*`, `term.freeze.default_mode` as `soft`, `hard` or `soft-then-hard`, the `term.freeze.*` times as whole seconds, and `term.freeze.drafts` and `term.freeze.busy` only as `skip` and `wait`.

#### Scenario: An option that waits for the owner
- **WHEN** `scripts/configure --set term.freeze.drafts=save` runs
- **THEN** it exits 2 saying the value waits for the owner's approval, and nothing is written

#### Scenario: Freeze defaults are not written
- **WHEN** `scripts/configure --get term.freeze.busy` runs and the key is not set
- **THEN** it prints `term.freeze.busy=wait` and writes nothing
