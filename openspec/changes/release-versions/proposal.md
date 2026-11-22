## Why
Homes take the base by merging `base/main`, with no versions, no standalone command, no dry run and no rollback. The owner asked (22.11) for home-base to be treated as an ordinary product with releases, so anyone can update their home to the newest or a chosen version when they want, without conflicts and without being bound by the base's choices.

## What Changes
- Releases: SemVer tags, `CHANGELOG.md`, GitHub releases; `main` moves only at a release. `VERSION` (flows) names the release a home is on.
- `scripts/base-update`: update to the newest release, `base.pin` or a chosen version; `--dry-run`, `--rollback`, `--check`. Base-owned paths always take the release's exact content; the home's edits to them are saved as a patch with where they belong. The `base-update` skill runs it.
- The sweep reports a newer release and drift against the release the home is on.
- README and the `CLAUDE.md` base block name the places a base update never touches.

## Impact
- `scripts/base-update` (new), `scripts/home-sweep`, `scripts/tests/base-update.test.sh` (new), `VERSION`, `CHANGELOG.md`, `base.manifest`, the `base-update` and `orchestrate` skills, `CLAUDE.md`, README.
