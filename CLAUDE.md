# Token Donation — build rules

You are building **Token Donation**. Read these before any work:

1. `SPEC.md`: **what** we're building, with GIVEN/WHEN/THEN acceptance criteria.
2. `POLICIES.md`: the **rules** the build must follow, each with an ID (LIFE / AGT / SEC / GIT / B).

## Non-negotiables
- Every change traces to a spec behaviour or a policy ID. Name the IDs in the commit or PR, e.g. `Implements LIFE-11, GIT-15` (B-01).
- Every MUST rule you implement gets a test or a written check named after its ID, e.g. `test_LIFE_11_claim_race` (B-02).
- Never silently diverge from the policies. To change a rule, edit `POLICIES.md`, and `SPEC.md` too if behaviour changes, in the same PR (B-03).
- Build in this order (B-04):
  1. the guardrails: SEC-06, SEC-07, SEC-08;
  2. claim and release: LIFE-11, GIT-15;
  3. checkpoints: AGT-07, AGT-08;
  4. everything else.
- Zero-setup principle: a helper needs only the repo, Claude Code and `gh`. Don't add anything they would have to install.
- Hooks are plain shell scripts with no dependencies. Their only network access is through `gh`, and `git` to `origin` (SEC-09). The hook plan is in `HOOKS.md`.
- Keep it simple. This is a hackathon v1: no features beyond `SPEC.md`, and nothing from the "Deferred to v2" list.

## Where the code lives (POLICIES.md D12)
- **Edit `src/`**: `src/hooks/*.sh`, `src/bin/td`, `src/claude-settings.json`. Tests run against `src/`.
- **Never edit `.td/hooks/`, `.td/bin/` or `.claude/settings.json` directly.** Those are the installed copy. The maintainer runs `src/install.sh` on `main` after merging.

## Dogfooding (POLICIES.md D9)
This repo is also the example project. The guardrail hook enforces SEC-07/08 **only on `td/*` task branches**. When you're building the tool on any other branch, you may edit `.claude/`, `.td/hooks/` and the rest freely.

## Hooks: what runs when (POLICIES.md D8)
No git hooks. Only Claude Code hooks, committed in `.claude/settings.json`. `Stop` runs after every reply, so it only syncs and never releases. `StopFailure` (`rate_limit`) and `SessionEnd` release the claim.

## Tests
Run `tests/run.sh`. Every test is named after the policy ID it proves.
