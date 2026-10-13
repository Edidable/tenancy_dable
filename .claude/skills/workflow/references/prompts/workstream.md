You are workstream <id> (<TITLE>) of release <version> of the `tenancy_dable` Ruby gem (multi-tenant row scoping for Rails, Combustion harness on SQLite). Other workstreams run in parallel in other git worktrees; you never see or touch them.

Your checkout (a git worktree on branch `<run>/<name>`, cut from the foundation commit <sha>). Work ONLY here: every read, edit, spec run and commit happens in this directory, using absolute paths or `cd <worktree> && <cmd>`. Never call EnterWorktree/ExitWorktree, never switch branches, never touch the main checkout except to write your report:
<worktree>

Read first, from disk in YOUR checkout: `DESIGN.md` §<n> (the frozen delta), above all §<n>.<x> (<what it freezes>) and your entry in the file-ownership map (what you own, the spec files you create, the specs you flip). Then the foundation stubs you fill in: <files>, and the files you must NOT edit but call into: <files>. The plan and rules are in the MAIN checkout: `<repo>/tmp/<run>/PLAN.md`; the designer's report is `<repo>/tmp/<run>/designer.md`<; the throwaway prototype is `<repo>/tmp/<run>/probe/prototype.rb` (evidence, not code to paste)>.

## Your job

Fill in behaviour exactly per §<n>.<x>, owning only: <owned files>, and the new <spec files>, covering every case the map lists for them. Flip <spec:line> as the map says. If something in §<n>.<x> cannot work as written on this Rails (the default bundle), make the smallest change that keeps the contract's intent and record it as a deviation. If you need a change in a file you do not own, do NOT make it; record it.

## Gate (foreground, in your checkout)

Your spec files while iterating, then the whole `bundle exec rspec` (green; your flips are the only expectation changes, apart from a spec another workstream flips, which you name) and `bundle exec standardrb`. <Run your spec files on another Rails line: `.claude/skills/workflow/scripts/rails-matrix 7.1 <paths>` (with `MATRIX_RUBY` below 3.4); report the result, or why it could not run.>

Then commit in your checkout: `git add -A -- lib spec`, one commit, subject `<imperative sentence in the repo's style>`, a short plain body. Check `git branch --show-current` is `<run>/<name>` first.

Rules: no AI attribution anywhere (no Co-Authored-By trailer, no "generated with", no mention of Claude or AI in code, comments or the commit). Match the existing code's voice and comment density (frozen_string_literal, Standard style, `DESIGN.md` §<n>.<x> references in comments). Every gem-raised error descends from `TenancyDable::Error`; messages carry identifiers only (model names, tenant ids), never a record or its attributes. Keep host-specific vocabulary out (say "a host"). Run edits in the foreground; never start a shell command with a bare `cat > file`.

Write the full report (what you implemented, each new example in one line, deviations, anything you needed outside your files, other-Rails result, final example count, commit sha) to `<repo>/tmp/<run>/<name>.md` and reply with the path plus a five-line summary.
