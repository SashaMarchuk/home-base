## MODIFIED Requirements

### Requirement: HOME-015 Read-only status
The `status` skill SHALL read only, covering this home and every related home whose role is `child` or `peer` through `scripts/home-status --all`, and report open issues grouped as needs you, only you can do, running, frozen (issues titled `Freeze <id>`, with how many sessions each holds and how many hold an open question of the owner), parked, can close, and the counts of ready and inbox, skipping issues labelled `dreams`, and list an open pull request labelled `dreams` under needs you.

#### Scenario: Owner asks for status
- **WHEN** the owner asks "status"
- **THEN** the answer is short plain text with empty groups left out, ending with the one thing the owner should do first

#### Scenario: An open Dreams pull request
- **WHEN** a pull request labelled `dreams` is open
- **THEN** it is listed under needs you, while the standing `dreams` issue stays skipped

#### Scenario: A freeze is open
- **WHEN** a `Freeze <id>` issue is open with five sessions, two of them holding a question
- **THEN** status lists it under Frozen with those two counts and not again under Parked

#### Scenario: A task started in a child home
- **WHEN** the owner opened a task straight in a child home and asks the parent for status
- **THEN** the parent's status shows that task with the child's name and number

## ADDED Requirements

### Requirement: HOME-440 One combined status across homes
`scripts/home-status` SHALL print one block `== <name> <repo> (<role>)` for this home and, with `--all`, for every related home whose role is `child` or `peer` (`--home <name>` adds a named one of any role); each block lists every open issue, `question` when it carries that home's owner label and else its state, without pull requests and issues labelled `dreams`, then one `session` line per open entry of that home's `.local/registry.json` (HOME-443).

#### Scenario: A child's question
- **WHEN** a child home's issue carries the owner label named in the child's own `home.config`
- **THEN** the child's block lists it as `question`, whatever label this home uses

#### Scenario: Sessions of a child
- **WHEN** the child's registry holds an open entry whose PID runs a command holding its match, one whose PID is gone, one with no PID yet, one marked lost and one closed entry
- **THEN** the block lists `live`, `stopped?`, `starting` and `lost` lines and leaves the closed entry out

#### Scenario: A parent home
- **WHEN** `home-status --all` runs in a home that names a parent home
- **THEN** the parent's issues are not read; `--home <parent name>` reads them

### Requirement: HOME-443 Session lines of the combined status
`scripts/home-status` SHALL print one `session <live|lost|stopped?|starting> <tty|-> <session id> #<issue|-> <role>` line per open registry entry: `lost` only for an entry `term.sh reconcile` marked lost (with its last tty), `live` when its PID runs a command holding its match, `stopped?` when that PID is gone (one signal, never called lost), `starting` with no PID yet.

#### Scenario: A lost and a stopped session
- **WHEN** one entry was marked lost by reconcile and another entry's PID is gone
- **THEN** the first is listed as `lost` with its last tty and the second as `stopped?`

### Requirement: HOME-441 Each home is read as its own scripts read it
`scripts/home-status` SHALL read a related home's owner label and `gh.config_dir` from that home's clone (`homes.<name>.path`, its `home.config` and `.local/config`) and run its reads from that folder, never with this home's or an inherited `GH_CONFIG_DIR`; it SHALL only read, never switch a GitHub account or run another home's scripts, and without a clone SHALL use `homes.<name>.repo`, the label `needs-owner`, no `GH_CONFIG_DIR` and print `sessions: unknown (<why>)`.

#### Scenario: No clone on this machine
- **WHEN** a related home has no `homes.<name>.path`
- **THEN** its issues are read from `homes.<name>.repo` and its sessions are printed as unknown

#### Scenario: A related home with no gh.config_dir
- **WHEN** this home sets `gh.config_dir` and a related home's clone sets none
- **THEN** the related home's issues are read from its folder with no `GH_CONFIG_DIR`, never with this home's

#### Scenario: Nothing is written
- **WHEN** `home-status --all` runs
- **THEN** no GitHub call other than a read is made and no file is written

### Requirement: HOME-442 An unreadable home is named
`scripts/home-status` SHALL print `issues: cannot read <repo>` when a home's issues cannot be read and `issues: none open` only when the read succeeded with no open issue, and SHALL exit 0 in both cases.

#### Scenario: GitHub refuses the read
- **WHEN** the read of a child's issues fails
- **THEN** its block says `issues: cannot read <repo>` and the status says so instead of reporting no issues
