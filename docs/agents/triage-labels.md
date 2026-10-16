# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning in this repo                                                                  |
| -------------------------- | -------------------- | ------------------------------------------------------------------------------------- |
| `needs-triage`             | `unknown`            | No other state fits yet; a prompt to look again, not a resting place                  |
| `needs-info`               | `pending decision`   | A human has to choose something before any work is correct                            |
| `ready-for-agent`          | `agent-ready`        | Specified well enough that an implementer could start now                             |
| `ready-for-human`          | `blocked`            | Not landable from an agent session: needs cluster state, a human push, or another repo |
| `wontfix`                  | `wontfix`            | Will not be actioned; a closing verdict, so applying it means closing the issue       |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Upstream, `needs-info` means waiting on the reporter for information. Here the reporter is the maintainer, so the wait is on their decision, not on missing facts: use `pending decision` when work cannot start until the maintainer chooses something.

## State labels with no triage role

The repo has more state labels than the five roles cover. The `triage-issues` skill is the authority on all of them, including the five above:

| Label                 | Meaning                                                                   |
| --------------------- | ------------------------------------------------------------------------- |
| `needs-investigation` | A symptom with no established cause; a fix written now would be a guess   |
| `in-review`           | An open PR closes this issue; holds only while that PR is open            |
| `stale`               | The body is contradicted by current `main` or live state; re-triage first |
| `backlog`             | The user has deprioritized it. Only the user applies this label           |

An issue carries **exactly one** state label. When moving an issue between states, remove the old label in the same `gh issue edit` that adds the new one.
