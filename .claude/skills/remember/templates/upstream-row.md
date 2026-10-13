<!--
TEMPLATE: a row in the table in docs/upstream.md. Delete this comment before saving.
- docs/upstream.md is the one file where dates, maintainer handles and issue links are the content; every other doc forbids them.
- Add the row the moment a local workaround ships. A gotcha whose CAUSE is a library gets a row; the gotcha points here.
- Columns: library, problem, kind, status, link, local workaround, next step.
  kind: bug | missing-feature | docs | behaviour-change.   status: not reported | issue open | PR open | merged | released | closed (a row is closed, never removed).
  link: the upstream issue or PR URL, or "none yet".
  local workaround: the file and the mechanism in the gem, e.g. "`lib/tenancy_dable/relation_extension.rb` reads literal pins from `where_clause.ast`".
  next step: the single next action, and the release that lets the workaround be deleted once known.
- Keep the problem short and in system terms (a sentence or a few): what the library does, with which input, and why it matters to this gem.
-->
| <Library, e.g. Active Record> | <What it does wrong or surprisingly, with which input, and why it matters here.> | <kind> | <status> | <URL or none yet> | <`lib/...` file and mechanism> | <next action; release that lets the workaround go> |
