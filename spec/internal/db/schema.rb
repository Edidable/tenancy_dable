# frozen_string_literal: true

# Combustion fixture schema — the four tables the whole test suite runs against.
# Frozen by DESIGN.md §8. **Bold** columns there are mandated by the PLAN
# contract; the rest are minimal test-support columns (see DESIGN.md §10-G/H).
#
# Deliberately NO db-level unique index on widgets[tenant_id, name]: Phase 08
# tests `validates_uniqueness_to_tenant` as the system-under-test, and a DB
# unique constraint would mask the model validation (DESIGN.md §8).
ActiveRecord::Schema.define do
  create_table :tenants, force: true do |t|
    t.string :slug, null: false # contract key (slug resolution)
    t.string :name              # test-support label
    t.timestamps
  end
  add_index :tenants, :slug, unique: true

  create_table :users, force: true do |t|
    t.string :email # test-support identity attr
    t.timestamps
  end
  add_index :users, :email, unique: true

  create_table :memberships, force: true do |t|
    t.references :user, null: false   # contract: user_id
    t.references :tenant, null: false # contract: tenant_id
    t.string :role, null: false       # contract: role
    t.timestamps
  end
  add_index :memberships, [:user_id, :tenant_id], unique: true # contract uniqueness

  create_table :widgets, force: true do |t|
    t.references :tenant, null: false # contract: tenant_id (the scope fk)
    t.string :name                    # contract: name
    t.references :parent              # self-ref -> exercises CrossTenantError (Phase 08)
    t.timestamps
  end
  add_index :widgets, [:tenant_id, :name] # non-unique: validates_uniqueness_to_tenant is the SUT
end
