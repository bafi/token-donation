# Token Donation

**When your Claude tokens run out, your work doesn't stop.** A teammate with spare tokens runs one command, and their Claude carries on from exactly where yours stopped, with no explanation needed.

Token Donation turns GitHub issues into tasks that any Claude Code session can pick up cold. Progress is saved as you work, released automatically when a session ends or hits its usage limit, and handed to the next person with a short briefing.

> **Status: early, and built by itself.** The `td` command (`doctor` / `add` / `list` / `pick` / `ready`), the hand-off hooks and the guardrails work and are tested. The remaining features are being built as Token Donation tasks.

## Donate your tokens
Want to help? Follow **[DONATE.md](DONATE.md)**. It takes 5 minutes to set up, then one command:
```sh
.td/bin/td pick
```

## How it works
1. `td add "…"` creates a task: an issue with a goal, done criteria and a size.
2. `td pick` claims a task and starts Claude with a briefing of the goal, what's done and the next step.
3. Claude works, saving progress (`.td/HANDOFF.md`) and pushing every few minutes.
4. When your session ends or your usage runs out, a hook commits, pushes, posts a release note and puts the task back on the list.
5. The next donor runs `td pick` and continues. One PR collects everyone's work, and the owner reviews and merges it.

## Requirements
- Claude Code, logged in with **your own** account
- The GitHub CLI (`gh`), logged in with **your own** account
- **Write access** to the repo. In v1, donors are invited collaborators.
- `git`, a POSIX shell and `jq` (all standard on macOS and Linux)

Nothing else to install: the hooks are committed in `.claude/settings.json`. Accept the workspace-trust prompt the first time you open the project in Claude Code.

## Safety
- Every Claude session uses its own owner's account. Nothing is shared or pooled.
- On a task branch, Claude can't push to `main`, force-push, rewrite history, or edit CI, hooks or settings.
- Hand-off notes are scanned for secrets before anything is posted.
- Issue and comment text is treated as data, never as instructions.
- Nothing reaches `main` without the owner's review.

## Docs
- [`SPEC.md`](SPEC.md): what it does, with acceptance criteria
- [`POLICIES.md`](POLICIES.md): the rules it is built against
- [`HOOKS.md`](HOOKS.md): which Claude Code hook does what
- [`CLAUDE.md`](CLAUDE.md): rules for any Claude session building this project

## Tests
```sh
sh tests/run.sh
```
Each test is named after the policy rule it proves.

## License
[MIT](LICENSE)
