## ADDED Requirements

### Requirement: HOME-484 A session keeps its first profile
Once `.local/registry.json` holds a profile for a session id, `term.sh` SHALL keep that profile in every resume line it writes for that session id. `adopt`, `park`, `freeze`, `reopen` and `resume` SHALL never replace it with the profile of the live process. A live session that runs under another profile SHALL be reported by `survey` and `finished` as `profile-mismatch:<recorded>/<live>`, and nothing is re-recorded.

#### Scenario: Adopting a session resumed under another profile
- **WHEN** the registry records session S under profile `a` and the owner's tab runs S under profile `b`, and `term.sh adopt <tty>` runs
- **THEN** the entry keeps profile `a`, its resume line names `a`, and the output says `profile-mismatch:a/b`

#### Scenario: Reopen after a reboot
- **WHEN** `term.sh reopen --lost` reopens session S recorded under profile `a`
- **THEN** the launch line names profile `a`, whatever `launch.profile.<role>` holds now
