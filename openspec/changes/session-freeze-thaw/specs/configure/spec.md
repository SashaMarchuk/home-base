## MODIFIED Requirements

### Requirement: HOME-137 One step changes a machine key
`scripts/configure --set <key>=<value>` SHALL change only `.local/config` and only the machine keys `launch.*`, `terminal_helpers`, `limits.reader`, `gh.config_dir`, `transcripts.*`, `term.sessions_dirs`, `term.groups`, `term.group.<name>.cwd`, `term.group.<name>.home` and `term.freeze.*`, check each value as an answer is checked (folders start with `/` or `~/`, group names are lower-case words, a group's home is `self` or a name of `homes.*`, `term.freeze.default_mode` is `soft`, `hard` or `soft-then-hard`, times are whole seconds, and `term.freeze.drafts` and `term.freeze.busy` accept only `skip` and `wait`), remove the key on an empty value, keep every other line, print `<key>=<effective value>`, and refuse with exit 2 and nothing written any other key or an invalid value; `--get <key>` prints the same line without writing.

#### Scenario: Worker profile set, then unset
- **WHEN** `scripts/configure --set launch.profile.worker=personal` runs twice, then `scripts/configure --set launch.profile.worker=` runs
- **THEN** after the first two runs `.local/config` holds one line `launch.profile.worker=personal` and prints it, and after the third that line is gone and `launch.profile.worker=` is printed

#### Scenario: Committed key refused
- **WHEN** `scripts/configure --set repo=example-org/other` runs
- **THEN** it exits 2 naming `repo` as a committed key, and neither `home.config` nor `.local/config` changes

#### Scenario: An option that waits for the owner
- **WHEN** `scripts/configure --set term.freeze.drafts=save` runs
- **THEN** it exits 2 saying the value waits for the owner's approval, and nothing is written

#### Scenario: Freeze defaults are not written
- **WHEN** `scripts/configure --get term.freeze.busy` runs and the key is not set
- **THEN** it prints `term.freeze.busy=wait` and writes nothing
