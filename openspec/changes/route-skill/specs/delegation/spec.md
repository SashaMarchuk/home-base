## ADDED Requirements

### Requirement: HOME-485 The route skill picks the owning home from the home tree, down only
When `home-tree.md` exists, the orchestrator SHALL pick the home that owns a new request with the `route` skill: the candidates are this home (found by its `repo=`) and the homes below it in the tree. One home below fits: its one issue is opened there and none here. Only this home fits, or none: here. Two or more fit, or the request holds two jobs for two homes: one question to the owner with the fitting homes as options, recommended first, and no issue until the answer. A request that fits only a home above or beside this one SHALL get no issue in that home; the owner is told which home owns it. A home below that this home cannot reach (no `homes.*` entry with its repo) is reached through the nearest reachable home on the path down to it. Without `home-tree.md`, HOME-444 (topics) applies.

#### Scenario: A grandchild's request
- **WHEN** the tree is `a -> b -> c`, this home is `a`, `home.config` names only `b`, and the request belongs to `c`
- **THEN** its one issue is opened in `b` and none in `a`

#### Scenario: A child is asked for its parent's work
- **WHEN** this home is a child and the request belongs only to its parent
- **THEN** no issue is opened anywhere, and the owner is told that the parent home owns it

#### Scenario: One job, two homes fit
- **WHEN** a single job fits two homes below this one
- **THEN** the owner gets one question naming both homes and no "split" option, and no issue is opened until the answer

### Requirement: HOME-486 A template of the home tree
The base SHALL ship `templates/home-tree.md`: a tree drawing of homes named by repo and one section per home with Domain, Belongs and Not here. `home-tree.md` in a home is the home's own file; a base update never writes it.

#### Scenario: A home without a tree
- **WHEN** a home has no `home-tree.md`
- **THEN** routing uses this home's boundary and `homes.<name>.topics` as before
