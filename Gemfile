# frozen_string_literal: true

source "https://rubygems.org"

# Specify gem dependencies in tenancy_dable.gemspec
gemspec

# CI matrix support: pin Rails to a specific line via RAILS_VERSION so the GitHub
# Actions matrix can verify the gemspec's Rails 7.1–8.x range. Unset (or
# "default") resolves the newest Rails the gemspec allows — exactly what a normal
# local `bundle install` does — so this is inert outside CI.
rails_version = ENV["RAILS_VERSION"]
if rails_version && !rails_version.empty? && rails_version != "default"
  gem "rails", "~> #{rails_version}.0"
end
