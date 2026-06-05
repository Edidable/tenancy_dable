# frozen_string_literal: true

# Shared harness for the generator specs.
#
# These specs deliberately stay on `spec_helper` (NOT `rails_helper`): booting
# Combustion sets `Rails.application`, which makes ActiveRecord's
# `db_migrate_path` resolve to the harness's ABSOLUTE `spec/internal/db/migrate`.
# `migration_template` would then write real migration files into the frozen test
# app instead of the throwaway destination. Driving the generators against an
# isolated tmp dir (spec_helper only) keeps every byte they emit disposable.
#
# Belt-and-suspenders: even in the FULL `bundle exec rspec` run (where another
# spec may already have booted Combustion before these examples execute),
# `run_generator` pins `db_migrate_path` to the relative "db/migrate" on the
# generator instance, so migrations always land under the tmp destination no
# matter what `Rails.application` reports.

require "rails/generators"
require "tmpdir"
require "fileutils"
require "stringio"
require "generators/tenancy_dable/install/install_generator"
require "generators/tenancy_dable/model/model_generator"

module GeneratorSpecHelpers
  # Build the generator and run all of its steps against `destination`, silencing
  # the Thor shell chatter. We use `new` + `invoke_all` (rather than `.start`) so
  # we can pin `db_migrate_path` on the instance before it runs (see file header).
  def run_generator(generator_class, args = [], destination:)
    generator = generator_class.new(args, {}, destination_root: destination)
    generator.define_singleton_method(:db_migrate_path) { "db/migrate" }
    silence_stdout { generator.invoke_all }
    generator
  end

  # Every file (absolute paths) the generators wrote under `root`.
  def files_under(root)
    Dir.glob(File.join(root, "**", "*")).select { |path| File.file?(path) }
  end

  # Read a generated file by its path relative to the destination root.
  def read_generated(root, relative)
    File.read(File.join(root, relative))
  end

  # Migration paths whose basename is `<timestamp>_<name>.rb` (timestamp-agnostic).
  def migration_paths(root, name)
    Dir.glob(File.join(root, "db", "migrate", "*_#{name}.rb"))
  end

  # The body of the one migration named `<name>` (raises unless exactly one).
  def migration_body(root, name)
    paths = migration_paths(root, name)
    raise "expected exactly one #{name} migration, found #{paths.size}" unless paths.size == 1
    File.read(paths.first)
  end

  # True when `source` parses as syntactically valid Ruby.
  def valid_ruby?(source)
    RubyVM::AbstractSyntaxTree.parse(source)
    true
  rescue SyntaxError
    false
  end

  # Seed a minimal host routes file so the route-scaffold injection (and its
  # idempotency) can be exercised.
  def seed_routes(root)
    FileUtils.mkdir_p(File.join(root, "config"))
    File.write(File.join(root, "config", "routes.rb"), "Rails.application.routes.draw do\nend\n")
  end

  private

  def silence_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end
end
