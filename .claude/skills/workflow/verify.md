# Step 4: Verify - refute the release, fix, verify again

Green specs prove what the builders thought of. This step hunts what they did not: agents prompted to refute the release's claims, a lead who decides what each finding becomes, fixers, and a final verify after the last fix. It is the step that turns a plausible release into a correct one, and it is never skipped for a change that touches a guard, the context facade or any security invariant (`docs/architecture.md`).

## 1. The two verifiers

Both `opus`, effort `high`, in this order: the red team first, the contract audit once the release docs have landed.

- **Red team** ([references/prompts/red-team.md](references/prompts/red-team.md)) - attacks the security invariants: cross-tenant reads, cross-tenant writes, fail-closed and bypass hygiene, fiber isolation, declarations. A finding counts only with a failing probe spec under `tmp/<run>/redteam/` (the probe asserts the SECURE behaviour, so it fails while the bug exists), run on every Rails line it can. Works in the main checkout, writes only under `tmp/<run>/redteam/`.
- **Contract and completeness audit** ([references/prompts/contract-audit.md](references/prompts/contract-audit.md)) - proves the release is not ready item by item: every spec item vs where it is implemented, proven and documented; code vs the `DESIGN.md` delta; docs vs code; counts and contract locks; `gem build` contents; hygiene; semver. Runs in its OWN detached worktree (`git worktree add --detach ../tenancy_dable-wt/audit HEAD` + the lockfile, created after the docs commit so it sees them), because the harness database is one file per checkout and two rspec processes in one checkout break each other.

The sequencing, in one place:

- The release-docs agent ([release.md](release.md) section 1) never runs specs, so it may run beside the red team while the red team's probes run in the main checkout.
- The contract amendment ([release.md](release.md) section 1) waits for the fix round, then runs in the main checkout only while no probe set or suite is running there; the audit's delta-versus-code findings feed that round.
- The audit runs in its own worktree once the docs land, so it checks them too.
- Nothing else runs rspec in a checkout while a probe set or the suite is running in it.

## 2. The fix round

The lead reads both reports in full and writes `tmp/<run>/fix-round.md`: every finding in exactly one bucket, with the decision and its reason.

| Bucket | Means |
|---|---|
| **Fixed in code** | the fix, the owner, the spec that proves it |
| **Docs only** | a claim that was wrong, or a behaviour the gem keeps by design (fail-open by default, a documented residual); the doc line that changes |
| **Deferred** | out of this release's scope; reported to the user at the end |

Weigh each code fix against what it can break: a fix that changes behaviour for every host (a marker that outlives a request, a refusal of a common idiom) needs more care than the finding it closes, and "document it and recommend the safer setting" is a legitimate decision. Record why.

Then the fixers: `sonnet`, effort `high`, one per area with disjoint ownership, each in its own worktree from the current branch head ([references/prompts/fixer.md](references/prompts/fixer.md)). Each fixer must make the probes of ITS findings pass and keep the whole suite green, then commits on `<run>/<fixer>`. The lead cherry-picks, runs the integration gate, and runs the full probe set.

## 3. The probes are the regression set

From the first red team on, the whole of `tmp/<run>/redteam/` runs after every fix round:

```
bundle exec rspec tmp/<run>/redteam/ -I spec --default-path spec
```

Keep the expected-failure list in `fix-round.md`: exactly the findings bucketed docs-only or deferred, plus any probe whose expectation the fix deliberately changed (a refusal where the probe expected a silent pass). Any other failure is a regression.

## 4. Final verify, and again after the last fix

When the fix round is integrated and the docs are amended, one `opus` agent, effort `high`, attacks the WHOLE release once more ([references/prompts/final-verify.md](references/prompts/final-verify.md)): the regression probes on every Rails line, over-refusal (ordinary own-tenant host code that the stricter guards may now break: associations, nested attributes, `touch: true`, `dependent:`, `find_or_create_by`, upserts with a tenant-including index, batches, `load_async`, cache keys, partial selects, case-insensitive uniqueness), new leaks in the fix-round code, docs vs code, the gem build.

Its findings go through another fix round. After the LAST fix, the same verifier re-verifies, scoped to the new diff, its repros and the regression set: never stop on a verdict about the code before the last fix. The release is ready only on a READY verdict about the final commit.

## 5. Accepted residuals

Everything the gem knowingly still allows (an explicit bypass, a shape indistinguishable from one, a fail-open default) is written in three places before release: the `DESIGN.md` delta's residual list, the README section of the guard, and the final report to the user. A residual a verifier showed reads data across tenants is said plainly as such, never folded into "the safe side".

## 6. Stop point `rc` (with the docs of release.md section 1)

The release candidate is: every fix round integrated, the final verify READY, the docs of [release.md](release.md) section 1 committed, the gates green, the branch clean. Hand the user what shipped, the decisions taken without asking, the accepted residuals, the deferred items, and the question whether to release. Nothing is pushed.
