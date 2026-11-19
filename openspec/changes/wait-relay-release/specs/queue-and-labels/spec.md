## ADDED Requirements

### Requirement: HOME-447 One session may release many changes
When several tasks change one repository, the decision whether their release (merge order, CI, the release itself) goes to one separate session with its own issue SHALL be the home's own, from how many changes wait and whether they touch each other.

#### Scenario: Five changes to one repository
- **WHEN** five finished tasks each left a change to the same repository
- **THEN** the orchestrator may open one release issue and session for them instead of five releases

### Requirement: HOME-448 A task carries its own pull request to green
A task that carries its own pull request SHALL keep it until every code-review comment is answered or fixed and every CI/CD check passed, and only then finish with the pull request's link, with no separate release session unless the owner says so; the brief of such a worker SHALL say this, and rule 6 still applies to each push and merge.

#### Scenario: CI fails after review
- **WHEN** a worker's pull request has all review comments answered but one CI check fails
- **THEN** the worker fixes it and does not finish until every check passed
