# frozen_string_literal: true

# `rake tenancy_dable:audit` (DESIGN.md §16.3). Loaded by the railtie's
# `rake_tasks` hook.
namespace :tenancy_dable do
  desc "Report models whose tenancy is undeclared or suspicious (exits 1 on findings)"
  task audit: :environment do
    findings = TenancyDable.audit
    abort(findings.join("\n")) if findings.any?
    puts "tenancy_dable:audit: every model declares its tenancy"
  end
end
