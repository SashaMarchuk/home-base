---
name: route
description: Decide which home owns a new request, this one or a home below it in the home tree, before any issue is opened. Use it first for every new owner request in a home (a home with no homes below it uses it too, to refuse work that belongs above or beside it), whenever a request may belong to another domain, when the owner asks "where does this go", "is this for <home>", "send this to the right home", and from step 0 of the orchestrate skill's section 7 and step 3 of the task skill. Reads `home-tree.md` and `home.config` only; it never routes up to a parent or across to a sibling.
---

# route

One request in, one answer out: **here**, **hand to `<repo>`**, or **one question**. Nothing is opened or claimed while routing; the answer decides where the one issue goes.

## Read
1. `home.config` (and `.local/config`, which overrides it): `repo=` is this home; each `homes.<name>.repo` / `.path` says which homes this home can reach.
2. `home-tree.md`: the tree drawing (every home, by its repo) and one section per home with **Domain**, **Belongs** and **Not here**. Every home holds the same tree, so find this home's node by its `repo=`.
   - No `home-tree.md`: use the older way. Compare the request with this home's domain and boundary (`## This home` in `CLAUDE.md`) and the `homes.<name>.topics` of the homes with `role=child`; continue at Decide. A `role=parent` or `role=peer` home is never a candidate, only recognised as the owner.
3. Candidates are this home and every home **below** it (children, grandchildren). Homes above or beside it are read only so you can recognise that a request is theirs.
4. A candidate's section is too thin to decide a request: read the `## This home` section of that home's `CLAUDE.md` (at `homes.<name>.path`) for its domain and boundary. Read nothing else there.

## Judge
Ask: **whose work is it, and where will its result live?** Not: which words does it mention.
- A personal errand that mentions a work word stays personal ("a birthday gift for my colleague from the work team" is personal).
- A request for a home's product, clients, team, board, repos, calls or chats belongs to that home, even when it names none of its topic words.
- A home fits when its **Belongs** covers the request, not merely when nothing in it excludes the request. A home that only might fit ("could be personal money too") is not an option.
- **Not here** wins over **Belongs**: a home whose section excludes the request does not fit, whatever else matches.
- A request with two separate jobs for two homes fits both.
- A home's tree section is the source; the topics in `home.config` are only hints.

## Decide
| What fits | Answer |
|---|---|
| Only this home, or no home at all | **here** |
| Exactly one home below | **hand to it** |
| Two or more candidates (this home included), or two jobs for two homes | **one question** |
| Only a home above or beside this one | **not mine**: one question, never a hand-off |

- **hand to it**: when the target has no `homes.<name>` entry here (a grandchild), hand to the nearest home on the path down to it that has one; that home routes again.
- **one question**: through the surface's ask tool, context first (what the request is and why it fits more than one home, in one line), the fitting homes as options, recommended first. Only when the request holds two separate jobs, add the option "split: one issue in each home"; one job that could belong to either home is never split, the owner picks its one home. Open nothing until the answer.
- **not mine**: say which home owns it and that a request for it starts in that home's session (or in a home above it). Never open an issue in a parent or a sibling: routing goes down only. Options, through the ask tool: "Stop here; I start it in <that home>" (recommended); then, when that home is a `role=peer` in this home's `home.config`, "Hand it over as a peer (a brief and links only)", otherwise "Stop, and give me a short brief to paste there"; and "Do it here anyway" only when this home's boundary does not exclude the request. The owner's pick of the peer option is the explicit order of the orchestrate skill's section 7 peer hand-off; nothing else is.

## Then
State the result in one line before acting: `route: here`, `route: <repo> (homes.<name>)`, `route: ask <home>|<home>` or `route: not mine, <repo>`.
- **here**: go on with the request (the `task` skill or orchestrate rule 1: the issue in this home).
- **hand to it**: orchestrate section 7, steps 1 to 3. The one issue goes there; none here.
- After an answer to the question: act on it as above.
