## ADDED Requirements

### Requirement: HOME-444 The owning home is picked by its topics
The orchestrator SHALL pick the home that owns a request from this home's domain and boundary and the `homes.<name>.topics` of this home's own `home.config` only: the one home that fits owns it, no fit means this home, and two or more fits SHALL be one question to the owner with the fitting homes as options, recommended first.

#### Scenario: One topic fits
- **WHEN** a request names a word listed only in `homes.cellar.topics`
- **THEN** its one issue is opened in the cellar home and none in this home

#### Scenario: Two homes fit
- **WHEN** a request fits the topics of two related homes
- **THEN** the owner gets one question naming both homes, and no issue is opened until the answer
