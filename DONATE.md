# Donate your Claude tokens

Thanks for helping! You'll use **your own** Claude account to carry on a task that someone else started. You don't need to know anything about the project: Token Donation briefs your Claude on where things stand. Setup takes about 5 minutes, once.

## 1. One-time setup

**You need:**
- [Claude Code](https://code.claude.com), logged in with your account
- [GitHub CLI](https://cli.github.com) (`gh`), logged in with your account
- `git` and `jq` (already on macOS 15+ and most Linux)

**Steps:**

1. **Accept the invite.** The owner invites you as a collaborator. Accept it from the GitHub email, or at https://github.com/bafi/token-donation/invitations.
2. **Log in to GitHub from the terminal** (skip if you already have):
   ```sh
   gh auth login
   ```
3. **Get the project:**
   ```sh
   git clone https://github.com/bafi/token-donation.git
   cd token-donation
   ```
4. **Check your setup:**
   ```sh
   .td/bin/td doctor
   ```
   Fix anything it marks `FIX`, then run it again until it says **All good**.

## 2. Donate (every time)

From inside the project folder:

```sh
.td/bin/td pick
```

1. **Choose a task.** You'll see the open tasks with their sizes (S, M or L). A good fit for your remaining tokens is recommended. Press Enter to take it, or type another number.
2. **Accept the trust prompt.** Claude Code opens. If it asks whether to trust this folder, say yes; this switches on the project's safety hooks.
3. **Let Claude work.** It reads a briefing (the goal, what's done, the next step) and carries on from there. You can watch, answer its questions, and approve or deny anything risky.
4. **Stop whenever you like.** Quit Claude, or simply run out of tokens. Your work is saved and pushed automatically, and the task goes back on the list for the next person. Nothing more to do.
5. **If you finish the task,** Claude runs `.td/bin/td ready`, which sends the work to the owner for review.

Other commands:

| Command | What it does |
|---|---|
| `.td/bin/td list` | See all tasks and who's on what |
| `.td/bin/td add "your idea"` | Suggest a new task (uses a few of your tokens to write it up) |

## What's safe, and what's yours

- **Your accounts stay yours.** Nothing is shared or pooled, and no token or password is ever stored or posted.
- **Claude is limited while on a task.** It can only push to the task's own branch. It can't touch `main`, rewrite history, or edit the project's CI, hooks or settings.
- **Secrets stay local.** Anything that looks like a secret is never posted to GitHub.
- **The owner reviews everything.** Nothing reaches `main` without the owner merging it.
- **You get credit.** The PR lists everyone who worked on the task.

## If something goes wrong

| You see | Do this |
|---|---|
| `you need write access` | Accept the collaborator invite (step 1) |
| `uncommitted changes` | `git stash`, then try again |
| `someone else claimed #N` | Run `.td/bin/td pick` again and choose another task |
| `Token Donation is paused` | The owner paused it. Try later |
| Claude says your claim was released | Your session ended or tokens ran out. Run `.td/bin/td pick` to continue |
| Anything else | Comment on the task's issue and mention the owner |
