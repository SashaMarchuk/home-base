# Accounts and profiles

The owner uses more than one CLI profile or workspace account. This page holds labels only: never an address. The mapping from a label to the real account stays in the named tool's own config, so nothing is stored twice.

| Label | Serves | Where the mapping lives |
|---|---|---|
{{ACCOUNT_ROWS}}

On this machine, `gh.config_dir` and `launch.profile.*` in `.local/config` select the account a script or a launched session uses. Never switch the CLI account by hand.
