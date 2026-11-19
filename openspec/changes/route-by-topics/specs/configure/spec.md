## ADDED Requirements

### Requirement: HOME-443 Topics of a related home
`scripts/configure` SHALL write each answered `homes.<name>.topics` into `home.config` next to that home's other keys and SHALL refuse, with exit 2 and nothing written, a value with an empty item, a `#` or a `=`.

#### Scenario: Topics answered
- **WHEN** the answers hold `homes.cellar.topics=cellar,wine list,bottling`
- **THEN** `home.config` holds that line as written

#### Scenario: An empty item
- **WHEN** the answers hold `homes.cellar.topics=cellar,,bottling`
- **THEN** configure exits 2 and names the key as an invalid answer
