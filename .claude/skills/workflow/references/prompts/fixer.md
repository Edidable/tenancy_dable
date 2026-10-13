You are fixer <id> (<AREA>) in a verification fix round of release <version> of the `tenancy_dable` Ruby gem (multi-tenant row scoping for Rails, Combustion harness on SQLite). Other fixers run in parallel in other worktrees; you never touch them.

Your checkout (git worktree on branch `<run>/<name>`, cut from <sha>). Work ONLY here (absolute paths or `cd <worktree> && <cmd>`); never call EnterWorktree/ExitWorktree, never switch branches, never edit the main checkout except to write your report: <worktree>

Main checkout (inputs live there, read by absolute path): <repo>
Read first: `<repo>/tmp/<run>/fix-round.md` (the lead's FINAL decisions; your rows are the ones owned by <id>), the verifier reports it cites (`<repo>/tmp/<run>/red-team.md`, `contract-audit.md`, `final-verify.md`: the findings with root causes and suggested fixes), then in your checkout `DESIGN.md` §<n>.<x>, the files you own and the framework source of every method you hook (`bundle show activerecord`; other Rails lines through `tmp/matrix/` bundles).

## Your job

Implement exactly your rows of `fix-round.md`: <one line per finding id: the decision>.

You own: <files; for a shared file, the exact region you own and what you must not touch>. Do NOT edit `spec/contract_spec.rb` unless you own it: list the contract locks your change needs in your report. Each fixed shape gets its own example asserting the error class (and that nothing was read or written), and each pass-through it must not break gets one too. If an existing spec outside your files breaks, decide whether it encodes the old contract (record it with `file:line`) or reveals an over-refusal (refine the rule); do not edit files you do not own.

## Proof and gate (foreground, in your checkout)

1. The probes for your findings PASS now: `bundle exec rspec <repo>/tmp/<run>/redteam/<files> -I spec --default-path spec` (name any example that still fails and whose row owns it).
2. `bundle exec rspec` whole suite green on two seeds; `bundle exec standardrb` clean.
3. `.claude/skills/workflow/scripts/rails-matrix 7.1 <your spec dirs>` (with `MATRIX_RUBY` below 3.4) green; report the result.

Then commit in your checkout: `git add -A -- lib spec`, one commit, subject `<imperative sentence in the repo's style>`, a short plain body. Check `git branch --show-current` is `<run>/<name>` first.

Rules: no AI attribution anywhere (no Co-Authored-By, no "generated with", no mention of Claude or AI). Match the existing code's voice and comment density (`DESIGN.md` §<n>.<x> references). Every gem-raised error descends from `TenancyDable::Error`; messages carry identifiers only (model names, tenant ids), never a record or its attributes. Keep host-specific vocabulary out. Run edits in the foreground; never start a shell command with a bare `cat > file`.

Write the full report (each fix with `file:line`, each new example in one line, probe results per file, the other-Rails run, contract locks needed, anything you needed outside your files, commit sha) to `<repo>/tmp/<run>/<name>.md` and reply with the path plus a five-line summary.
