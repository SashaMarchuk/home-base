## Why
With one issue per task in the home that owns the work, the orchestrator that receives a request must pick that home. Today it judges by the boundaries alone. A short list of words per related home makes the choice plain and lets the owner steer it; a request that fits more than one home is one question, never a guess.

## What Changes
- A committed, repeatable key `homes.<name>.topics=<comma-separated words>` beside `homes.<name>.repo|path|role`, written by `scripts/configure` from the answers and checked there (no empty item, no `#` or `=`). It lives only in the routing home's own `home.config`; no home reads another home's topics.
- The orchestrator (section 7, step 0) and the `task` skill pick the owning home from this home's domain and boundary and the topics: one fit owns it, none means this home, two or more fits (or a topic against this home's own domain) are one question with the fitting homes as options, recommended first.

## Impact
- `templates/home.config`, `templates/answers.example`, `scripts/configure`, its tests, the `configure`, `orchestrate` and `task` skills, README.
