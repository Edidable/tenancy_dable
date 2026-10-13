<!--
TEMPLATE: docs/domains/<name>.md  (the hub of one domain). Delete every HTML comment before saving.
- The filename IS the contract: it must equal the paired rule's filename (.claude/rules/<name>.md).
- Flat domain: keep the `##` sections below and drop `## Spokes`.
  Hub-and-spoke domain: keep only the overview, the principles and `## Spokes`; the depth lives in docs/domains/<name>/*.md.
- Write in Narrative Anchors ([LABEL:value] inside complete sentences; see ../narrative-anchors.md).
- Present tense, no run/phase/finding ids, no person, no date, no "since X", no derivable number (.claude/rules/docs.md).
- A hub is an overview and principles. Anything that needs a table of cases, a decision tree or a long list of residuals is a spoke.
-->
# <Domain>: <one-line scope>

<2 to 4 sentences: what this domain is in the gem, which layers read or write it, and what a reader will find below. Name the main class or file with an anchor, e.g. the engine lives in [FILE:lib/tenancy_dable/<file>.rb].>

## Spokes

<!-- Hub-and-spoke only. One line per spoke; a spoke the hub does not link here will not surface. -->
- [SPOKE:docs/domains/<name>/<subtopic>.md] holds <what the spoke covers, in one clause>.

## <Principle or behaviour>

<The domain's rules in prose with anchors: [METHOD:...], [CLASS:...], [ERROR:...], [CONFIG:...], [RULE:...]. State the behaviour, then the rationale in system terms ("raises because a foreign tenant id is never user input in a correct host"). Name the spec that proves it with [SPEC:spec/<dir>/<file>_spec.rb]. State absences explicitly with [ABSENCE:...] and accepted gaps with [RESIDUAL:...].>

## Gotchas

<!-- Only for a trap that belongs to this domain; delete the section otherwise. One `###` heading per gotcha, each ONE paragraph (see gotcha-entry.md). -->
### Gotcha: <short title naming the trap>

[SYMPTOM:<what a developer or a test sees>]. [CAUSE:<the mechanism>]. [FIX:<what the code or the caller does>]. [RULE:<the standing instruction>].
