## MODIFIED Requirements

### Requirement: HOME-068 Bash guard
The pre-tool hook for shell commands SHALL block with exit 2 and a reason any command that kills by pattern or more than one process (only one optional signal and single positive process ids above 1 reach the ownership check of HOME-350), switches the CLI account, force-pushes the default branch, deletes a repository, changes its visibility, pushes to the base remote, or matches a regex in `guard.extra`.

#### Scenario: Kill by pattern
- **WHEN** a session runs `kill $(pgrep node)`
- **THEN** the command is blocked

#### Scenario: Kill by pattern inside another command
- **WHEN** a session runs `bash -c "pkill node"` or `/usr/bin/killall Dock`
- **THEN** the command is blocked

#### Scenario: Signal by name to an exact id
- **WHEN** a session runs `kill -s TERM 1234`
- **THEN** the command is not blocked for its form and goes to the ownership check

#### Scenario: Account switch
- **WHEN** a session runs `gh auth switch`
- **THEN** the command is blocked and the reason names the configured account rule

#### Scenario: A kill of every process or of a group
- **WHEN** a session runs `kill -9 -1`, `kill 0`, `/bin/kill -9 -1` or `for p in $list; do kill $p; done`
- **THEN** the hook blocks it with exit 2

#### Scenario: A kill inside a shell string or after a background command
- **WHEN** a session runs `sh -c "kill -9 -1"` or `true & kill 0`
- **THEN** the hook blocks it with exit 2

#### Scenario: The same kill behind a prefix
- **WHEN** a session runs `/bin/sh -c "kill -9 -1"`, `bash -c -- 'kill -9 -1'`, `FOO=1 kill -9 -1`, `"kill" -9 -1`, `\kill 0`, `>/dev/null kill 0`, `/usr/bin/env kill 0`, `if kill 0; then :; fi` or `a & b & kill 0`
- **THEN** the hook blocks it with exit 2, and the same forms with an exact process id go to the ownership check

#### Scenario: A kill through xargs with options
- **WHEN** a session runs `echo 5 | xargs -n 1 kill`
- **THEN** the hook blocks it with exit 2

#### Scenario: An option after a process id
- **WHEN** a session runs `kill 1234 -0`, `kill 1234 -l` or `kill 1234 -5678`
- **THEN** the hook blocks it with exit 2, because the shell reads options only before the first process id

## ADDED Requirements

### Requirement: HOME-350 Kill of the session's own processes
The bash guard SHALL let a kill of exact process ids pass silently only when every target is a descendant of the calling agent session (the nearest process above the hook whose command is `claude` or `codex`) or the process of an open entry in this home's `.local/registry.json` that is not an adopted tab and whose recorded tty and command match still fit the live process.

#### Scenario: A process the session started
- **WHEN** a session runs `kill 1234` and process 1234 is a child or a deeper descendant of that session
- **THEN** the hook exits 0 and prints nothing

#### Scenario: A tab this home opened
- **WHEN** process 1234 is the pid of an open registry entry and runs on the entry's tty with a command line that contains the entry's match
- **THEN** the hook exits 0 and prints nothing

#### Scenario: A reused process id
- **WHEN** the registry names process 1234 but that process runs on another tty or its command line no longer contains the entry's match
- **THEN** the kill is not passed silently

#### Scenario: One foreign id among own ids
- **WHEN** a session runs `kill 1234 5678` and only 1234 is its own
- **THEN** the kill is not passed silently

#### Scenario: The agent process itself
- **WHEN** a session runs a kill of the agent process it runs in
- **THEN** the kill is not passed silently

### Requirement: HOME-351 Kill of any other process
For a kill of an exact process id that HOME-350 does not pass, the bash guard SHALL answer Claude Code with the pre-tool decision `ask` and a reason that names each such id and its command, in every permission mode, and SHALL refuse on Codex with exit 2 and a reason that tells the agent to ask the owner to run the kill.

#### Scenario: Claude Code
- **WHEN** a Claude Code session runs `kill 1234` and process 1234 is neither its descendant nor a registry entry
- **THEN** the hook exits 0 and prints one JSON object whose `hookSpecificOutput.permissionDecision` is `ask` and whose reason names 1234 and its command

#### Scenario: Codex
- **WHEN** the same kill reaches the guard through the Codex pre-tool hook, or the calling agent process is `codex`
- **THEN** the hook exits 2, prints no decision, and the reason says to ask the owner to run the kill

#### Scenario: No one to answer
- **WHEN** Claude Code runs without a user who can answer the prompt, in `bypassPermissions` mode included
- **THEN** the answer is still `ask`, which Claude Code turns into a denial

#### Scenario: Another rule blocks the same command
- **WHEN** the command also matches a block rule of HOME-068
- **THEN** the hook exits 2 and prints no `ask`

### Requirement: HOME-352 Undetermined ownership is refused
The bash guard SHALL refuse a kill of an exact process id with exit 2 on every surface when it cannot determine ownership: `ps` fails, the target is not running, no agent process is found above the hook and the registry does not vouch for the target, or the registry cannot be read as a list.

#### Scenario: No process list
- **WHEN** `ps` is missing or fails
- **THEN** the hook exits 2 and prints no `ask`

#### Scenario: Unreadable registry
- **WHEN** `.local/registry.json` exists but is not a JSON list and the target is not a descendant of the session
- **THEN** the hook exits 2

#### Scenario: No registry file
- **WHEN** `.local/registry.json` does not exist
- **THEN** the registry vouches for no process and the descendant check alone decides

#### Scenario: The target is gone
- **WHEN** no process has the target id
- **THEN** the hook exits 2 and the reason says there is nothing to kill

### Requirement: HOME-354 A kill the guard cannot read
When the word `kill` stands in a command where the bash guard cannot read it as `kill`, one optional signal and exact process ids, the guard SHALL answer as HOME-351 does (Claude Code: `ask`; Codex, or no agent process found: exit 2), except after `echo`, `printf`, `grep`, `egrep`, `fgrep`, `rg`, `git`, `gh`, `cat`, `man`, `which`, `type`, `ls`, `cd` and `home-log`, and where a plain word follows `kill` and no bare number or variable comes after it (never after `xargs`).

#### Scenario: A kill behind another command
- **WHEN** a Claude Code session runs `timeout 5 kill 1234`, `nice kill 1234`, `trap 'kill 1234' EXIT`, `case x in x) kill 1234;; esac`, `f() { kill 1234; }; f` or `sudo -u x kill 1234`, whoever owns process 1234
- **THEN** the hook exits 0 and prints the decision `ask` with a reason that quotes the command it could not read

#### Scenario: The same on Codex
- **WHEN** `timeout 5 kill 1234` reaches the guard through the Codex pre-tool hook
- **THEN** the hook exits 2 and prints no decision

#### Scenario: The word in text
- **WHEN** a session runs `git commit -m "kill the bug"`, `grep kill file`, `echo kill me` or `mytool --note "kill it softly"`
- **THEN** the hook exits 0 and prints nothing

#### Scenario: Text with a number after the word
- **WHEN** a session runs `mytool --note "we kill 12 of them"`
- **THEN** the guard cannot tell it from a kill and answers as for a kill behind another command

### Requirement: HOME-353 Liveness probe
The bash guard SHALL let signal 0 (`kill -0`, `kill -s 0`, `kill -n 0`) and a signal listing (`kill -l`) pass for exact process ids without the ownership check, because they end no process.

#### Scenario: Probe of a foreign process
- **WHEN** a session runs `kill -0 1234` and process 1234 is not its own
- **THEN** the hook exits 0 and prints nothing

#### Scenario: Probe of a group
- **WHEN** a session runs `kill -0 -1`
- **THEN** the hook blocks it with exit 2
