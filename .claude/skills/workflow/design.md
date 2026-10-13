# Step 2: Design - prove the problem, freeze the contract

Parallel builders who never talk to each other can only converge on a contract written down before they start. This step writes it: a delta section in `DESIGN.md` that freezes every name, signature, default, rule and error the release adds, and a file-ownership map that lets the build run in parallel without two agents ever editing one file.

## 1. The designer

One `opus` agent, effort `high` ([references/prompts/designer.md](references/prompts/designer.md)). In `solo` the session does it. The designer works in the main checkout, edits only `DESIGN.md` and `tmp/<run>/`, and commits nothing.

## 2. Prove the problem first

Every bug or leak item is reproduced before it is designed against: a throwaway probe spec under `tmp/<run>/probe/` (gitignored), run with

```
bundle exec rspec tmp/<run>/probe/<file>_spec.rb -I spec --default-path spec
```

requiring `rails_helper` like any spec. The probe states what it measured (shape -> result) and, where the spec claims it, on every Rails line it can run ([gates.md](gates.md) -> "Another Rails line"). A probe that does not reproduce changes the plan: the item is reworded, narrowed or dropped, and the user hears why.

A throwaway prototype of the proposed rule (a prepend loaded with `-r ./tmp/<run>/probe/prototype.rb`) run against the whole suite is the cheapest way to learn which existing specs the change flips. Those flips are named in the contract.

## 3. The delta section

Append `## <n>. vX.Y.Z delta - <what it adds>` after the last section of `DESIGN.md`, in the voice of the previous deltas: a preface naming what it amends, one subsection per item, a contract-impact summary, the contract-spec delta, and the file-ownership map. Write it in bounded chunks (one subsection per edit) to stay under the output cap.

Each item subsection freezes:

- exact constant names, method signatures, visibility and return shapes;
- every new setting with its default and its `validate!` rule;
- every new error with its parent (always under `TenancyDable::Error`);
- every guard as an ordered decision tree, and its documented residuals;
- I18n keys and locale paths, event names and payload keys;
- the existing specs whose expectations flip, by `file:line`.

When the spec is wrong, unsafe or contradicts the existing contract, the delta says so and decides; it never silently follows the spec.

## 4. The file-ownership map

The last subsection of the delta. A serial **foundation** lands every shared edit and the whole public shape as inert stubs (constants, signatures, call sites, value objects; stub bodies keep the previous behaviour), so the contract spec is green from the foundation commit on. Then N parallel **workstreams**, each owning a disjoint set of files:

- every file has exactly one owner during the parallel stage;
- a file two workstreams would touch moves into the foundation, or one owns it and the other is told what not to touch;
- per workstream: the files it owns, the spec files it creates, the existing specs it flips;
- nobody in the parallel stage edits `version.rb`, `README.md`, `UPGRADING.md`, `CHANGELOG.md` (the docs step), `spec/support/**`, `spec/rails_helper.rb`, `spec/spec_helper.rb` or `spec/internal/**` (foundation's).

Typical workstreams follow the domains (`docs/domains/`): scoping guards, declarations/audit, the context facade, i18n, a model concern.

## 5. Review and commit

The lead reads the designer's report and the delta in full, amends what it disagrees with (a decision the plan already took, a missing case), and commits only `DESIGN.md`:

```
git add DESIGN.md
git commit -m "Freeze the vX.Y.Z contract in DESIGN.md §<n>" -m "<one paragraph: what the delta adds, and that it carries the ownership map>"
```

## 6. Stop point `design`

With destination `design`, hand the user the commit, what the probes proved (including anything the spec missed), the decisions the delta took and the open risks, then end the turn. Otherwise continue to [build.md](build.md).
