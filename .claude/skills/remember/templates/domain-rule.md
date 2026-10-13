---
paths:
  - "lib/tenancy_dable/<file>.rb"
  - "spec/<dir>/**"
---
<!--
TEMPLATE: .claude/rules/<name>.md  (the rule paired with docs/domains/<name>.md). Delete this comment and every placeholder line before saving.
- SAME filename as the hub. Keep the `paths:` frontmatter: it is what auto-loads the rule when the domain's code is edited.
  List the domain's lib files and its spec directories, nothing broader (a rule that loads on every edit is noise).
- 8 to 25 lines, one fact per line, terse, no bullets needed. Invariants, traps, "if you change X also change Y".
- Never repeat the hub's prose; this is the cheat sheet an agent reads mid-edit.
- Same ban as docs: no run/phase/finding id, no person, no date, no derivable number.
- The LAST line points at the hub.
-->
<Invariant: what must always hold, naming the class or setting.>
<Trap: the thing that looks right and is wrong, and the correct move.>
<Always/never: "Never X; do Y instead.">
<If you change X, also change Y (the spec, the contract_spec list, the README section).>
Proof: `spec/<dir>/<file>_spec.rb`.
Narrative: docs/domains/<name>.md
