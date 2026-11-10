# Token Donation — Spec (v1)

## Problem
When a teammate's Claude tokens run out mid-task, the work stops. The context lives in their head and their chat history, so nobody else can carry it on.

## Goal
Any teammate with spare Claude tokens can open the project, run one command, and carry on with work they know nothing about. Nobody has to explain anything to them and there is nothing to set up.

## Users
- **Owner**: the teammate who started a task, either by working on it or by adding it to the list.
- **Helper**: a teammate who donates their own tokens to work on someone else's task. Over the life of a task, many helpers may work on it one after another.
- **Team**: everyone using Token Donation on the project.

## Prerequisites (for a helper)
- The project repo is already on their machine.
- Claude Code is installed and logged in with **their own** account.
- The GitHub CLI (`gh`) is logged in with **their own** GitHub account.
- Nothing else needs to be installed or configured.
- They are an invited **collaborator** (write access) on the repo. The repo itself can be public (open source) or private, and it has been set up once for Token Donation (see POLICIES.md §5).

## Behaviours

### 1. Tasks appear automatically
- When any session working on a task stops, including when tokens run out, its progress is saved and the task appears on the list as available. The person stopping does nothing.
- Saved progress includes the goal, the done criteria, what has been done so far, the exact next step, an estimated remaining size, and the contributors so far.

### 2. Adding tasks up front
- Anyone can add a task by describing it in plain words.
- Token Donation turns the description into a task that someone new to the code can start on. The task has a goal, done criteria and an estimated size.
- If the description is too vague to have checkable done criteria, Token Donation asks the describer up to 3 clarifying questions. If it is still too vague, the task is saved as a **draft**, which isn't on the list, with what's missing written down.

### 3. Picking up work
- A helper runs one command in the project and sees the list of available tasks with a short summary of each.
- Token Donation detects how many tokens the helper has left and recommends the task that fits best.
- If it can't detect the budget, it asks the helper once ("roughly how much can you spend: a little / a lot?") and recommends based on the answer.
- If no task fits, it recommends a **slice**: the next step of a larger task, sized so the helper can finish it.
- After choosing, the helper sees a short briefing (goal, what's done, the next step, previous contributors). Their Claude then starts working on its own. The helper can watch or step in.

### 4. Claims
- Picking a task claims it. Others see it as taken and can't pick it.
- The owner coming back with fresh tokens sees who has the task. They can pick it up again once it's released.
- If a helper stops cleanly, including when their tokens run out, their progress is saved, the claim is released, and the task goes back on the list.
- If a session ends without a clean stop (crash, laptop closed, network loss), the claim is released automatically after **30 minutes** of inactivity. The task goes back on the list from its last saved progress, marked "last session ended unexpectedly".

### 5. Returning work
- Each task has **one PR**. The first helper opens it, and later helpers add to the same PR.
- The PR lists every contributor and what each one did.

### 6. Finishing
- When the done criteria are met, the task moves to **awaiting review** and leaves the pick-up list.
- The task is done only when the owner merges or closes the PR.
- If the owner requests changes, the task goes back on the list, and the owner's review comments become its next step.
- If the owner closes the PR without merging, the task is **cancelled**. Only the owner can reopen it.

### 6b. Needs owner
- A task that is stuck goes to **needs-owner**, which takes it off the list, and the owner is notified. A task counts as stuck when any of these happen:
  - the same step fails in 2 sessions in a row;
  - the task crashes 3 times with no progress;
  - it goes through 3 review rounds;
  - its criteria are unclear;
  - it needs something outside the repo.
- The owner clarifies, rescopes or cancels it.

### 7. Credit
- Each task and its PR show a contributor list. There are no leaderboards or totals.

### 8. Web dashboard (view only)
- Shows every task with its status, size, current claimant, progress, contributors and PR link.
- Claiming, adding tasks and working all happen from the terminal, not the dashboard.

### 9. Notifications
| Event | Who is notified |
|---|---|
| New task available (session stopped or task added) | Team |
| Task picked up | Owner |
| Task ready for review | Owner |
| Changes requested (task back on the list) | Team |
| Task needs the owner (stuck or blocked) | Owner |

## Out of scope (v1)
- People outside the team (strangers, public donors), and therefore sandboxing and protecting donors.
- Hiding code from helpers. Helpers see the whole repo, as teammates normally do.
- Sharing or pooling Claude accounts. Each person always uses their own.
- Claiming, adding or working on tasks from the web dashboard.
- Leaderboards and token totals.

## Decided (see POLICIES.md)
- Stuck-claim timeout: 30 minutes without activity.
- Size display: S / M / L with a rough token range.
- Vague descriptions: up to 3 clarifying questions, then the task is saved as a draft.
- PR closed without merging: the task is cancelled.

## Open questions
- Where notifications arrive (GitHub notifications, Slack, email…).

---

## Acceptance criteria

### Automatic hand-off
- **GIVEN** a teammate is working on a task **WHEN** their tokens run out **THEN** the task's progress (goal, done criteria, work done, next step, estimated remaining size, contributors) is saved and the task appears as available, with no action from them.
- **GIVEN** a teammate is working on a task **WHEN** they end the session normally **THEN** the same progress is saved and the task appears as available.

### Adding tasks
- **GIVEN** a teammate in the project **WHEN** they describe a task in plain words **THEN** a task with a goal, done criteria and estimated size appears on the list as available, with them as owner.
- **GIVEN** a description too vague for checkable done criteria **WHEN** the describer still can't clarify it after 3 questions **THEN** the task is saved as a draft that isn't on the list, with what's missing listed, and nobody is notified.

### Picking up
- **GIVEN** a helper with the repo and a logged-in Claude Code **WHEN** they run the pick-up command **THEN** they see the available tasks with a short summary of each, without installing or configuring anything else.
- **GIVEN** a detectable token budget **WHEN** the helper opens the list **THEN** the task that best fits their budget is recommended.
- **GIVEN** the budget can't be detected **WHEN** the helper opens the list **THEN** they're asked once how much they can spend, and a task is recommended based on their answer.
- **GIVEN** no available task fits the helper's budget **WHEN** they open the list **THEN** a slice (the next step of a larger task) is recommended.
- **GIVEN** a helper chooses a task **WHEN** it opens **THEN** they see the goal, what's done, the next step and previous contributors, and Claude starts on the next step without further input.
- **GIVEN** no tasks are available **WHEN** a helper runs the pick-up command **THEN** they're told nothing is available right now.

### Claims
- **GIVEN** a helper picks a task **WHEN** another teammate views the list **THEN** that task shows as claimed by the helper and can't be picked.
- **GIVEN** a task claimed by a helper **WHEN** the owner returns **THEN** the owner sees who has it and can't pick it until it's released.
- **GIVEN** a helper is working on a task **WHEN** their tokens run out or they stop cleanly **THEN** their progress is saved, the claim is released, and the task is back on the list from the new next step.
- **GIVEN** a helper's session ended without a clean stop **WHEN** the inactivity period passes **THEN** the claim is released and the task is back on the list from its last saved progress, marked "last session ended unexpectedly".

### Returning work
- **GIVEN** the first helper works on a task **WHEN** they save progress **THEN** a PR is opened for the task.
- **GIVEN** a task that already has an open PR **WHEN** a later helper works on it **THEN** their work is added to the same PR, and no new PR is opened.
- **GIVEN** several helpers have worked on a task **WHEN** anyone views the task or its PR **THEN** every contributor is listed with what they did.

### Finishing
- **GIVEN** a helper's Claude meets the task's done criteria **WHEN** it finishes **THEN** the task moves to "awaiting review" and no longer appears on the pick-up list.
- **GIVEN** a task awaiting review **WHEN** the owner merges the PR **THEN** the task is done.
- **GIVEN** a task awaiting review **WHEN** the owner requests changes **THEN** the task is back on the list, and the review comments are its next step.
- **GIVEN** a task with an open PR **WHEN** the owner closes the PR without merging **THEN** the task is cancelled and leaves the list.
- **GIVEN** a task whose same step has failed in 2 sessions in a row, or that crashed 3 times with no progress, or went through 3 review rounds **WHEN** this happens **THEN** the task moves to needs-owner, leaves the list, and the owner is notified.

### Dashboard
- **GIVEN** any teammate opens the dashboard **WHEN** it loads **THEN** they see every task with its status, size, claimant, progress, contributors and PR link.
- **GIVEN** a teammate on the dashboard **WHEN** they look for a way to claim, add or work on a task **THEN** there is none; those actions happen in the terminal.

### Notifications
- **GIVEN** a session stops or a task is added **WHEN** the task becomes available **THEN** the team is notified.
- **GIVEN** an owner's task **WHEN** a helper picks it up **THEN** the owner is notified.
- **GIVEN** an owner's task **WHEN** it moves to "awaiting review" **THEN** the owner is notified.
- **GIVEN** an owner requests changes **WHEN** the task goes back on the list **THEN** the team is notified.
- **GIVEN** an owner's task **WHEN** it moves to needs-owner **THEN** the owner is notified.

### Boundaries
- **GIVEN** any helper **WHEN** they work on a task **THEN** they use their own Claude account; no account or login is shared.
