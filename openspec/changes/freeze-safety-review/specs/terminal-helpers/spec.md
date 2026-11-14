## MODIFIED Requirements

### Requirement: HOME-302 Where a session id comes from
`term.sh` SHALL take a tab's session id from this home's registry only while the entry's pid is the live process and the session file names no other id, else from its session file, else its command line; freeze keeps a tab whose registry entry no longer matches as `kept:changed`, and a tab with no id SHALL get no resume line.

#### Scenario: No session file and no id
- **WHEN** a tab runs `claude -r` and no session file exists for its process
- **THEN** `survey --json` gives it no session id and no resume line

#### Scenario: A new session in a reused tab
- **WHEN** the session this home opened in a tab exited and a new `claude` session runs in the same tab
- **THEN** freeze sends that tab no key and lists it as `kept:changed`
