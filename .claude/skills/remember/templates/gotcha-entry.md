<!--
TEMPLATE: a gotcha. Delete this comment before saving.
- Shape: its OWN `### Gotcha: <short title>` heading and ONE paragraph under it carrying [SYMPTOM:...], [CAUSE:...], [FIX:...] and, when there is one, [RULE:...]. Never an inline `[GOTCHA:...]` buried in a longer section.
- Home: the domain hub or spoke it belongs to (flat doc, hub or spoke alike), grouped under a `## Gotchas` heading. docs/gotchas.md only if it cuts ACROSS domains (a single-domain trap stays in its domain doc).
- Admit it only if a future change can reintroduce the trap and it names something in the repo. A resolved bug with nothing left to watch is git history.
- The conclusion, never the diary: no measurements, no "verified with", no story of how it was found, no run or finding id.
- Each anchor sits in its own sentence, as the docs write them: `[SYMPTOM:...]. [CAUSE:...]. [FIX:...]. [RULE:...].`
- If the CAUSE is a library, also add a row to docs/upstream.md (upstream-row.md) and point at it.
- [RULE:...] is optional; include it when there is a standing instruction ("never X", "if you change X also change Y").
-->
### Gotcha: <short title naming the trap>

[SYMPTOM:<what a developer or a test sees>]. [CAUSE:<the mechanism, in system terms, naming the class, setting or Active Record behaviour>]. [FIX:<what the code or the caller does about it>]. [RULE:<the standing instruction for the next change>].
