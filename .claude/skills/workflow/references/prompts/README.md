# Prompt templates

One fill-in prompt per agent role of the workflow. Replace every `<placeholder>`; delete a line that does not apply rather than leaving a placeholder in. Each template already carries the rules every prompt needs ([../../orchestrate.md](../../orchestrate.md) -> "Prompts"): the checkout and branch, owned / read-only / forbidden files, the gate, no AI attribution, nothing private, the report line.

| Template | Role | Pin | Step |
|---|---|---|---|
| [designer.md](designer.md) | prove the problem, write the `DESIGN.md` delta and ownership map | `opus`, `high` | design |
| [foundation.md](foundation.md) | the shared pieces and the inert stubs | `sonnet`, `high` | build |
| [workstream.md](workstream.md) | one workstream in its worktree | `sonnet`, `high` (or `medium`) | build |
| [red-team.md](red-team.md) | refute the security invariants | `opus`, `high` | verify |
| [contract-audit.md](contract-audit.md) | prove the release is not ready, item by item | `opus`, `high` | verify |
| [fixer.md](fixer.md) | fix one bucket of findings | `sonnet`, `high` | verify |
| [docs.md](docs.md) | README, UPGRADING, CHANGELOG | `sonnet`, `medium` | release |
| [final-verify.md](final-verify.md) | the last adversarial pass, and the re-verify after the last fix | `opus`, `high` | verify |

Common placeholders: `<repo>` = the main checkout's absolute path, `<run>` = the target version without dots (`v060` for `v0.6.0`), `<version>` = `0.6.0`, `<branch>` = the run's branch, `<spec>` = the proposal file's absolute path, `<n>` = the delta's section number.
