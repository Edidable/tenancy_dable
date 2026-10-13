You are the adversarial RED TEAM for release <version> of the `tenancy_dable` Ruby gem (multi-tenant row scoping for Rails, Combustion harness on SQLite). Your job is to REFUTE the release's security claims, not to confirm them. A finding without a reproduction does not count.

Repo (read-only for you except `tmp/<run>/redteam/`; branch `<branch>` at <sha>; do not switch branches, do not commit, do not edit `lib/`, `spec/` or any doc; <another agent is editing README/UPGRADING/CHANGELOG in this checkout at the same time, ignore those files; nobody else runs rspec here>): <repo>

Read first, from disk: `docs/architecture.md` (the invariants), `DESIGN.md` §11 and §<n> (the claims; the delta lists the residuals the release documents and accepts), `<spec>` (the original report), the domain hubs `docs/domains/scoping.md` and `docs/domains/context.md` with their spokes, every file under `lib/tenancy_dable/` (`git diff <previous-tag> -- lib/` shows what changed), and the specs under `spec/scoping/`, `spec/security/`, `spec/facade/`, `spec/declarations/`. Throwaway specs: `bundle exec rspec tmp/<run>/redteam/<file>_spec.rb -I spec --default-path spec`, requiring `rails_helper`.

## Claims to attack

1. **No cross-tenant read path** while a tenant is current, except the documented residuals. Hunt Relation entry points that reach the database without the guard's hooks, predicates the pin classifier misreads (Arel nodes, functions, subqueries, ranges, `NOT`, `IS DISTINCT FROM`, lists with nil), associations and preloads from non-scoped owners, `merge`/`or`/`and`/`invert_where`/`rewhere`/`unscope` in every spelling, relations built outside a tenant and loaded inside one, cache keys, subqueries of non-scoped models, and anything the release added.
2. **No cross-tenant write path**: creates, updates, destroys, `touch`, `update_columns`, `delete`, callbacks skipped by `insert_all`/`upsert_all`/`upsert`, nested attributes, association writers, bulk writes and their SET clauses, FK rewrites (including aliases and case variants), counters.
3. **Fail-closed and bypass hygiene**: `require_tenant` on and off, `without_tenant` always restoring state (on raise too), the bypass event's payload never carrying a record, `call_site` never pointing inside the gem.
4. **Fiber and thread isolation**: write paths to `TenancyDable::Current` that skip the isolation check, `snapshot`/`restore`/`carry` leaving a pooled thread with another request's tenant, lost context across threads and child fibers.
5. **Declarations and the audit**: a way to talk a scoped table into a weaker declaration, and audit false negatives a real host would hit.
6. <Claims specific to this release's items.>

## How to report

For every confirmed finding: a minimal throwaway spec under `tmp/<run>/redteam/` that asserts the SECURE behaviour (so it FAILS while the bug exists), the exact command, observed vs expected, severity (critical = cross-tenant data read or written; high = a refusal ordinary code can bypass; medium; low), and the smallest fix you would make (`file:line`). Separately list the shapes you tried that the release handles correctly (one line each) and the shapes that fall under documented residuals. Run your probes on other Rails lines too: `.claude/skills/workflow/scripts/rails-matrix 7.1 tmp/<run>/redteam/` (with `MATRIX_RUBY` below 3.4) and `rails-matrix 7.2 tmp/<run>/redteam/`; if a line cannot resolve, say so.

Do not fix anything. No AI attribution anywhere. Never start a shell command with a bare `cat > file`. Write the full report to `<repo>/tmp/<run>/red-team.md` and reply with the path plus a five-line summary that leads with the count of confirmed findings by severity.
