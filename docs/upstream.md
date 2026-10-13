# Upstream ledger

> The living record of problems whose root cause is inside a dependency. A workaround ships with the code that needed it; the fix belongs to the library. Add a row the moment you write a workaround for a library bug, advance it as the upstream work moves, and close it when the fix is released on a line the gem supports and the workaround is removed or kept on its own merits. Rows are closed, never removed. Only genuine library bugs belong here; a decision this gem made, or a Rails behaviour that is correct but surprising, is documented in `docs/decisions.md` or the domain doc instead.

This file is the one carve-out in `docs/` from the rule against tracker links, handles and dates: an upstream issue link, a maintainer's handle and a release date are the content of its rows. The libraries the rows draw from are listed in [FILE:docs/stack.md].

## Status vocabulary

| Status | Meaning |
|---|---|
| `not reported` | Problem confirmed in the library, no upstream contact yet. |
| `issue open` | An issue or discussion exists upstream. |
| `PR open` | A pull request is open upstream. |
| `merged` | Merged on the library's development branch. Changes nothing here yet. |
| `released` | Shipped in a version the gem supports. The local workaround is removable, or its remaining reason is stated in the row. |
| `closed` | The fix is released, the workaround is removed or kept on its own merits, and the spec that pinned it is updated. |

Kinds: `bug` (a pull request with a failing test), `docs` (a documentation pull request), `missing-feature` (an issue or discussion first), `behaviour-change` (a discussion first).

## Rows

| Library | Problem | Kind | Status | Link | Local workaround | Next step |
|---|---|---|---|---|---|---|
| Active Record (`ActiveRecord::Relation::WhereClause#to_h`, reached through `Relation#where_values_hash`) | `to_h(table_name)` calls `node.left.relation.name` on every top-level equality, so an equality whose left side is not a column (`Arel::Nodes::NamedFunction`, a `SqlLiteral`, a `Quoted`) raises `NoMethodError: undefined method 'relation'`, and Rails' own case-insensitive uniqueness validation builds exactly that (`lower(name) = lower(?)`), as does `where(Model.arel_table[:name].lower.eq("x"))`. Reproduced on the 8.1 line, where `where_values_hash`, `scope_for_create` and `new` on such a relation raise the same `NoMethodError`. | `bug` | `not reported` | none yet | `lib/tenancy_dable/relation_extension.rb` never calls `where_values_hash`: the classifier reads the tenant column's literal pins from `where_clause.ast`, recursing into `Arel::Nodes::And` and keeping equality nodes whose left side is an `Arel::Attributes::Attribute` named the tenant column on the model's table. Pinned by the examples under "the classifier reads literal pins from the where clause" in `spec/scoping/read_guard_spec.rb`. | Reproduce on Rails main with a failing test in the `WhereClause` tests (`to_h` with a function equality and a table name), then open a pull request that skips a node whose left side has no `relation`. When the fix is released the row moves to `released`; the workaround stays, because reading literal pins from the AST is also what lets the classifier ignore a non-literal equality beside a pin (the join condition of `eager_load`), which `where_values_hash`'s last-wins value would hide. |
