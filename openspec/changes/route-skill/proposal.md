## Why
The owner starts most tasks from the top home, also work that belongs to a home below it. He asked for a short base skill that decides, the same way every time, whether a request stays in the home where it was started or goes to a home below. It must be home-agnostic: it reads a personal description of the tree of homes and acts on it. Routing goes down only: nobody starts a parent's task from a child.

Today step 0 of the orchestrate skill's section 7 (HOME-444, change `route-by-topics`) picks the home from this home's boundary and a list of words per related home (`homes.<name>.topics`). Words alone cannot tell "a birthday gift for my colleague from the work team" (personal) from work, they say nothing about grandchildren, and a child that receives a parent's request has no rule that stops it from handing the request up.

## Design (decided)
- **The tree lives in its own file, `home-tree.md`, at the root of each home.** It is the home's own file (not base-owned): a tree drawing like the `tree` command, then one section per home with Domain, Belongs and Not here. A flat `key=value` file cannot draw a tree, and a domain needs a few lines of prose. The base ships a generic template, `templates/home-tree.md`.
- **Every home holds the same copy.** Each home finds itself in it by its own `repo=`. Nodes are named by their GitHub repo, because the names under `homes.*` differ per home (one home's `homes.sf` is another home's nothing). The join to a reachable home is `homes.<name>.repo`.
- **Candidates are this home and the homes below it.** Homes above or beside are read only to recognise "this is theirs": the skill then says which home owns it and opens no issue (no hand-up, no hand-across). The explicit owner order "hand this to the peer" stays as it was (section 7 peer hand-off); it is not routing.
- **The question is whose work it is, not which words it uses.** A home fits when its Belongs covers the request; Not here wins over Belongs; a home that only might fit is not an option. One fit below: hand to it. Only this home or nothing: here. Two fits, or two jobs for two homes: one ask-tool question with the fitting homes as options, recommended first, and a "split" option only for two separate jobs.
- **A grandchild** that this home cannot reach (no `homes.*` entry) is reached through the nearest home on the path down that it can reach; that home routes again.
- **Other homes' `CLAUDE.md`.** The skill may read the `## This home` section of a candidate's `CLAUDE.md` when the tree's lines are too thin; the tree stays the source. Reading whole files of other homes was rejected: they are long, mostly about how the home works, and they would leak one domain's detail into another's session.
- **Topics stay as the fallback** for a home without `home-tree.md`, so no home breaks on update. With a tree, topics are ignored; one source decides.
- **A home's copy and its boundary.** A home's copy needs full Belongs/Not here lines only for itself and the homes below it; the others may be one line, so every copy passes its own boundary check.

## What Changes
- New base skill `.claude/skills/route/` (flows to every home), HOME-485.
- New template `templates/home-tree.md` (a generic three-level example), HOME-486.
- Orchestrate section 7 step 0 and task step 3 call the route skill. `CLAUDE.md` base block: `route` among the skills, `home-tree.md` in "Where things live" and among the home's own places.
- `templates/home.config` and README: topics are the fallback when there is no `home-tree.md`.

## Evaluation (built with the skill-creator eval loop)
Sixteen cases run in dry-run copies of homes built from the real base block and skills (stub `home-log` and `term.sh` that only record their arguments), with the skill and without it (the current step 0 with topics). Real-home cases: clear work, clear company, clear personal, an ambiguous notes-bot request, a request with jobs for two homes, a personal request that names the work, a work word used for a personal purchase, an unlabelled invoice, a child asked for its parent's work and a child asked for its peer's work, and the same two child cases in a child without `home-tree.md` (the fallback). An invented three-level tree (no shared words) covers a grandchild, a grandchild without keywords, a sibling and an ambiguous request. Five rounds; the skill was tightened three times ("do it here anyway" only when the boundary allows it; a home fits only when its Belongs covers the request, and "split" only for two jobs; a leaf home uses the skill too, the fallback never takes a parent or peer, and "not mine" always has a second option). Final round on the released text: 16 of 16, and the four ambiguous cases run twice gave the same answer (20 of 20 runs). Without the skill: 9 of 14 (it handed work up to a parent twice, across to a peer once, and offered homes or a split that did not fit twice). The cases and the fixtures stay out of the base.

## Impact
- `.claude/skills/route/SKILL.md`, `templates/home-tree.md`, `base.manifest`, `CLAUDE.md`, the `orchestrate` and `task` skills, `templates/home.config`, README.
- Homes: no step by hand is required; a home that wants tree routing adds its `home-tree.md` (with topics they keep working as before).
