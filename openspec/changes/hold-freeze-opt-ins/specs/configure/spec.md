## MODIFIED Requirements

### Requirement: HOME-323 Values of the session keys
`scripts/configure --set` SHALL accept `term.sessions_dirs` and `term.group.<name>.cwd` as folders starting with `/` or `~/`, `term.groups` as lower-case names, `term.group.<name>.home` as `self` or a name of `homes.*`, `term.freeze.default_mode` as `soft`, `hard` or `soft-then-hard`, the `term.freeze.*` times as whole seconds, `term.freeze.drafts` as `skip` or `save`, and `term.freeze.busy` as `wait` or `interrupt`.

#### Scenario: An option that waits for the owner
- **WHEN** the owner has approved this change and `scripts/configure --set term.freeze.drafts=save` runs
- **THEN** `.local/config` holds `term.freeze.drafts=save`

#### Scenario: Freeze defaults are not written
- **WHEN** `scripts/configure --get term.freeze.busy` runs and the key is not set
- **THEN** it prints `term.freeze.busy=wait` and writes nothing
