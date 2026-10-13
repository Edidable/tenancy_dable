<!--
TEMPLATE: docs/domains/<name>/<subtopic>.md  (a spoke of a hub-and-spoke domain). Delete every HTML comment before saving.
- The back-link line sits directly under the H1, exactly as below (`> Part of the [<name> domain](../<name>.md).`).
- Add the spoke's one-line entry to the hub's `## Spokes` map in the same edit; an unlinked spoke is invisible (doc_parity.rb fails on it).
- Narrative Anchors, present tense, no narration, no derivable numbers (.claude/rules/docs.md).
- A spoke is the depth: decision trees, case tables, residuals, per-spec proof. The hub keeps the overview.
- A trap that belongs to this subtopic is its own `### Gotcha: <short title>` heading with ONE paragraph (see gotcha-entry.md), grouped under `## Gotchas`.
-->
# <Name>: <subtopic>

> Part of the [<name> domain](../<name>.md).

<1 to 3 sentences: what this subtopic is and where it sits in the domain.>

## <Behaviour>

<Prose with anchors. For a decision tree, a numbered list of branches in the order the code runs them, each naming its [ERROR:...] or [METHOD:...]. Cite the frozen contract sparingly: "the signatures are frozen in `DESIGN.md` §N".>

## Residuals

<!-- Delete this section if there are none. -->
<What the gem does not guarantee here, stated as a fact: [RESIDUAL:short name] followed by what happens and why it is accepted. Never a to-do, never a tracker reference.>

## Gotchas

<!-- Delete this section if there are none. One `###` heading per gotcha, each ONE paragraph. -->
### Gotcha: <short title naming the trap>

[SYMPTOM:<what a developer or a test sees>]. [CAUSE:<the mechanism, in system terms>]. [FIX:<what the code or the caller does about it>]. [RULE:<the standing instruction for the next change>].

## Proof

<The specs that weld this subtopic: [SPEC:spec/<dir>/<file>_spec.rb] for ...; name the spec instead of counting examples.>
