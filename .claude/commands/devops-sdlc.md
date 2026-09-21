# DevOps SDLC Workflow

Guide the user through a complete DevOps task lifecycle in 4 phases. Execute phases in order. Do not skip ahead. At each phase gate, confirm with user before proceeding.

---

## Phase 1 — Jira Ticket Update

Ask the user for the Jira ticket ID if not already provided in the command args (`/devops-sdlc SPARK-123`).

Prompt the user to confirm or supply:
- **Summary** — one-line description of the task
- **Description** — what needs to be done and why (acceptance criteria)
- **Labels** — e.g. `devops`, `migration`, `infra`, `helm`
- **Assignee** — default: current user
- **Status transition** — move ticket to `In Progress`

Output the Jira fields as a summary block so user can copy-paste or confirm before updating:

```
Ticket:      <ID>
Summary:     <text>
Status:      In Progress
Labels:      <labels>
Description: <text>
```

Ask: "Update Jira with these values? (yes / adjust)"

---

## Phase 2 — Planning & Design

Before writing any code, produce a written plan. Structure:

1. **Problem statement** — what the task requires (1–2 sentences)
2. **Approach** — chosen solution and why (vs alternatives considered)
3. **Affected files/components** — list with purpose of each change
4. **Dependencies** — services, secrets, config values, external APIs involved
5. **Risks** — anything that could break; mitigation per risk
6. **Rollback** — how to undo if deploy fails
7. **Open questions** — blockers or assumptions needing confirmation

Present plan to user. Ask: "Proceed with implementation? (yes / adjust plan)"

Do not write any code until user approves plan.

---

## Phase 3 — Implementation

Implement the approved plan. Follow these rules:

- Edit existing files; create new ones only when necessary
- No comments unless WHY is non-obvious
- No speculative features beyond task scope
- No backwards-compat shims for removed code
- For shell scripts: use `set -euo pipefail`
- For Helm: merge via values layering, never patch templates directly
- For Terraform/OpenTofu: prefer variable inputs over hardcoded values

After implementing, run any available linters or syntax checks.

Report: files changed, lines added/removed, any errors encountered.

Then automatically commit all changed files:
- Stage only the files modified by this task (not unrelated files)
- Commit message format: `feat(<scope>): <one-line summary>` — use conventional commits
- Do NOT add Co-Authored-By lines; git config already has correct author identity
- Do NOT use `--no-gpg-sign` or any extra flags; commit normally

Then automatically create a PR using `gh pr create`:
- Title: `feat(<scope>): <one-line summary>` matching the commit
- Base branch: `main`
- Body must include:
  - `## Summary` — bullet list of what changed and why
  - `## How to enable` — any config/variable changes needed by operators
  - `## Rollback` — exact steps to revert
  - `## Test plan` — checklist of items to verify
  - `Closes <TICKET-ID>` at bottom
- Return the PR URL to the user

Ask: "Ready to test? (yes / fix something)"

---

## Phase 4 — Testing

Run through this checklist. Check each item and report pass/fail:

### Automated
- [ ] Lint / syntax check passes (yamllint, shellcheck, helm lint, tofu validate)
- [ ] Existing tests pass (if test suite present)
- [ ] New tests written for new behaviour (if applicable)

### Manual / Integration
- [ ] Dry-run or `--debug` output reviewed for correctness
- [ ] Change tested in non-prod environment (or document why not possible)
- [ ] Rollback path verified (can the change be reverted cleanly?)

### Jira close-out
- [ ] PR/MR linked to ticket
- [ ] Ticket status → `Done` (or `In Review` if PR pending merge)
- [ ] Any follow-up tasks captured as new tickets

Report final status. If all pass: "SDLC complete. Ticket <ID> closed."
If any fail: list failures, stop, wait for user direction.
