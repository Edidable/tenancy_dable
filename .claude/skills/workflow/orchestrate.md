# Orchestrate: the multi-agent policy of this repo

With `orchestrate`, the session is the **lead**: it decomposes the work, hands the substantive pieces to pinned agents, reads every result before deciding the next phase, integrates, and owns every commit, merge and long gate. This file is the whole policy for multi-agent work in this repo, inside a `/workflow` run or not. If a personal orchestration skill disagrees, this file wins.

The lead works turn by turn with the `Agent` tool, so it can read each report and stop to ask the user. A Workflow script is used only when the user asks for one by name.

## Model and effort, fixed at spawn

Every `Agent` call passes `model` and `effort`. An unpinned agent inherits the session's model, and a fleet of those spends the top tier on work the mid tier does as well.

| Role | `model` | `effort` |
|---|---|---|
| foundation, workstreams, fixers, docs, contract amendments, mechanical sweeps | `sonnet` | `high` for guards and the facade, `medium` otherwise, `low` for mechanical work |
| designer, red team, contract audit, final verify | `opus` | `high`; one agent per stage, never a fleet |
| anything | `fable` | only when the user names it, on the stages they name |

A `fork` always runs on the session's model; use it only for a side task that needs the whole conversation (drafting from what was discussed), never to spread work.

## A flat tree

Only the lead creates agents; agents do not create agents. A grandchild's completion notice goes to the top session, not to the agent that spawned it, so a sub-lead waiting for it never wakes. Keep the number running at once to what the phase needs.

Name an agent only when it will receive a `SendMessage` later (a verifier asked to re-verify after the last fix). With agent teams enabled, a named `Agent` call becomes a teammate; that is fine for a verifier kept for a re-verify, never for builders sharing files.

## Worktrees: the lead creates them

Isolation is cheap here: a worktree needs only the lockfile copied in ([build.md](build.md) section 2). The rules:

- **The lead creates and removes every worktree**, as siblings under `../tenancy_dable-wt/<name>` on `<run>/<name>` branches (or `--detach` for a read-only verifier). Agents work in them by absolute path (`cd <abs path> && <cmd>`).
- **Never `isolation: "worktree"`** on an `Agent` call: the lead loses control of the base commit and the branch name, and that agent cannot write a report outside its worktree.
- **No agent calls `EnterWorktree` or `ExitWorktree`**: one that does moves the whole session.
- **One rspec process per checkout.** The harness database is a single file per checkout, recreated on boot (`docs/domains/testing.md`); two runs in one checkout break each other. An agent that runs specs either owns its checkout or runs while nobody else in that checkout does: nothing else runs rspec in a checkout while a probe set or the suite is running there. The red team runs first and may run probes in the main checkout; the contract audit runs in its OWN worktree; the release-docs agent never runs specs and may run beside the red team ([verify.md](verify.md) section 1).

## Ownership

Parallel agents never share a mutable file. The delta's ownership map ([design.md](design.md) section 4) assigns every file to one owner; each prompt lists the files the agent owns, the files it may only read, and the files it must not touch. When two would need the same file, they run in sequence, or the shared edit moves into the foundation.

## What stays with the lead

- **Commits on the run's branch, cherry-picks, merges, tags, pushes.** Agents commit only on their own `<run>/<name>` branch (or, in the main checkout, only when their prompt says so).
- **Long gates and CI.** The integration gate, the probe sets and every CI watch run from the lead, in a background shell writing to a file. An agent that starts a long job in the background goes idle and never comes back for its output; agents run bounded spec sets in the foreground.
- **Decisions.** The fix-round buckets, which residuals are accepted, whether a finding is fixed or documented.
- **The stop point.**

## Prompts

An agent shares none of the lead's context, so every prompt carries: the goal; the checkout's absolute path and branch; the spec and plan paths; the delta subsection it implements; the files it owns, may read and must not touch; the gate commands; the conventions; and the report line. The templates in [references/prompts/](references/prompts/) carry all of it. Four details belong in every prompt they apply to:

- **No AI attribution**, word for word from [git.md](git.md), in every prompt that writes a commit or any text that leaves the machine.
- **Instruction files are a snapshot.** An agent receives the `CLAUDE.md`, rules and skills of the session's start. If the run edited any of them, tell the agent to read them from disk.
- **Large files.** An agent asked to emit one whole large file dies at the output cap after a long silence. Ask for bounded chunks (a skeleton, then an edit per section).
- **Background shells.** A command that begins with a bare `cat > file` (no heredoc, no input) waits on stdin forever and keeps the session's background work open. Agents run Python or Ruby edits in the foreground and write files with the Write/Edit tools.

## Reports

Every prompt ends with the same line: the full report goes to `tmp/<run>/<agent>.md` (in the main checkout, by absolute path, even for an agent working in a worktree), and the reply carries the path plus a five-line summary. A notification truncates a long reply. Read the file, not the notification, then tell the agent it is done and should not resend; an idle agent otherwise drains its queue and repeats itself.

Idle notifications arriving after an agent's work was integrated are stale: acknowledge, do not act on them twice.

## Verify what comes back

An agent's "done" is a claim. The lead re-runs the gate the agent claims to have run, reads the library diff of every commit before integrating it, and sends anything consequential (a guard, the facade, a security edge) to an `opus` verifier prompted to refute ([verify.md](verify.md)). In a fix-then-verify loop, verify once more after the LAST fix.

## Plan mode

An agent spawned while plan mode is on is read-only and can write exactly one file, `<plan-file-stem>-agent-<name>-<hash>.md` beside the session plan file: name that path in its prompt and read it from there. The `tmp/<run>/` report convention starts after `ExitPlanMode`.
