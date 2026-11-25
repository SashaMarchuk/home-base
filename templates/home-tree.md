# Home tree

Every home keeps the same copy of this file. The `route` skill reads it to decide whether a new request stays in this home or goes to a home below it. Routing goes down only: a home never hands a request to the home above it or to one beside it.

Each home is named by its GitHub repo. A home reaches another only through its own `homes.<name>.repo` in `home.config`.

```text
you/personal-home       your personal life; the orchestrator over the homes below
├── you/work-home       your job: sprints, releases, on-call
│   └── you/team-home   one team inside the job: its board and its releases
└── you/club-home       the volunteer club: members, newsletter, events
```

## you/personal-home
- Domain: your personal life, and the orchestrator over the homes below.
- Belongs: errands, health, travel, money, family, personal projects, the setup of the homes themselves.
- Not here: work of any home below.

## you/work-home
- Domain: your job.
- Belongs: sprints, releases, on-call, the job's repos, calls and chats.
- Not here: personal errands that only mention a colleague; the club.

## you/team-home
- Domain: one team inside the job.
- Belongs: that team's board, its releases and its calls.
- Not here: the job's work outside this team.

## you/club-home
- Domain: the volunteer club.
- Belongs: members, the newsletter, events.
- Not here: the job; personal errands.

<!-- A home's copy needs the full Belongs and Not here lines only for itself and the homes below it; a home above or beside it may be one line. Every line must pass this home's own boundary check (scripts/checks/run). -->
