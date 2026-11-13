# Decisions

Append-only. One entry per decision of the owner, newest last. An agent's default is not a decision: it goes to an owner issue instead. Supersede an entry by adding a new one and changing only the old entry's `Status:` line.

Entry format:

```
### <ID> Short title
- Quote: "the owner's words, verbatim"
- Gloss: English rendering, required when the quote is not in English
- Source: where the words were said (issue link, session id, document)
- Supersedes: <older ID> | none
- Status: active | superseded-by <newer ID>
- Kind: owner | delegated
- Decider: (Kind: delegated only) who decided, under the delegating quote above
```

<!-- entries below -->
