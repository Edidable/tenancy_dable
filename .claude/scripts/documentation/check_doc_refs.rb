#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "set"
require_relative "code_index"

# Deterministic doc->code guard: every namespaced Ruby constant a doc names must
# resolve to an in-repo definition (under lib/, spec/internal/ or spec/support/)
# or belong to a known external namespace. A doc names a constant two ways, and
# both are read: in backticks (`TenancyDable::Foo`) and as the value of a
# Narrative Anchor whose value starts with a namespaced constant
# (`[CLASS:TenancyDable::Foo]`, `[ERROR:...]`, `[MODULE:...]`, `[CONST:A::B::C]`,
# `[METHOD:TenancyDable::Audit.run]` yields `TenancyDable::Audit`).
# Three modes (plain `ruby`, no bundle):
#   - hook: reads a PostToolUse JSON payload on stdin, checks only the edited
#           .md file's added refs; the edit is already applied, so a bad
#           reference is flagged with exit 2 and the agent fixes it.
#   - full: `--all` (or no stdin), scans the whole docs tree, exits 1 on any miss.
#   - prune: `--unused`, lists .doc-refs-allow entries no doc references any more.
#
# Scope: it resolves paths against CLAUDE_PROJECT_DIR, so an edit made inside a
# sibling worktree (../tenancy_dable-wt/*) is not checked by the hook; run
# `--all` in that worktree instead.
#
# A token whose LAST segment resolves but whose full name does not is reported as
# a WARNING, not a pass: that is a constant that moved between namespaces.

DOC_GLOBS = %w[docs/**/*.md .claude/rules/*.md CLAUDE.md].freeze

# Top-level namespaces provided by Rails, gems the docs mention, or Ruby itself.
# Refs under these are external and exempt from in-repo resolution. `TenancyDable`
# is deliberately absent: it is this repo's own code.
EXTERNAL_NAMESPACES = %w[
  ActiveRecord ActiveSupport ActiveModel ActionController ActionCable ActionDispatch
  ActionView ActionMailer ActiveJob ActiveStorage Rails Arel Pundit I18n Rack
  Async Fiber Thread Data Combustion FactoryBot RSpec Standard RuboCop Rake Bundler Gem
  Zeitwerk SQLite3 Sqlite3 PG Mysql2 Sidekiq SolidQueue GoodJob Puma Falcon Warden Devise
  Kernel Comparable Enumerable Enumerator Object BasicObject Module Class Method Proc
  Hash Array String Symbol Integer Float Numeric Rational Complex Range Regexp Struct
  Set Time Date DateTime JSON YAML Psych ERB URI Net Logger SecureRandom Digest OpenSSL
  Mutex Monitor Ractor Process GC ObjectSpace Marshal File Dir IO Pathname StringIO
  Tempfile Open3 Timeout Benchmark Forwardable Singleton Delegator SimpleDelegator
  StandardError RuntimeError ArgumentError NameError NoMethodError TypeError KeyError
  FrozenError NotImplementedError Errno Exception Warning
].to_set.freeze

NAMESPACED_RE = /\A[A-Z]\w*(?:::[A-Z]\w*)+\z/

def project_root
  ENV["CLAUDE_PROJECT_DIR"] || Dir.pwd
end

def backtick_tokens(text)
  text.scan(/`([^`\n]+)`/).flatten.map(&:strip)
end

# Everything a line names as a constant: backticked tokens and the namespaced
# constants that Narrative Anchors start with.
def doc_tokens(text)
  backtick_tokens(text) + DocSync::CodeIndex.anchor_constants(text)
end

def namespaced_constant?(token)
  NAMESPACED_RE.match?(token)
end

# :external, :exact, :short (resolves under a DIFFERENT namespace), or :miss.
def resolution(token, index)
  parts = token.split("::")
  return :external if EXTERNAL_NAMESPACES.include?(parts.first)
  return :exact if index[:fqn].include?(token)
  return :exact if index[:fqn].any? { |fqn| fqn.end_with?("::#{token}") }
  return :short if index[:short].include?(parts.last)

  :miss
end

def resolves?(token, index)
  resolution(token, index) != :miss
end

# Curated exceptions: references that intentionally do not resolve in-repo
# (illustrative example classes, a removed name a decision records on purpose).
# This file is the reviewed registry of "known non-refs".
def allow_list
  @allow_list ||= begin
    file = File.join(project_root, ".claude", "scripts", "documentation", ".doc-refs-allow")
    if File.file?(file)
      File.readlines(file).map(&:strip).reject { |l| l.empty? || l.start_with?("#") }.to_set
    else
      Set.new
    end
  end
end

def classified_in(text, index)
  doc_tokens(text)
    .select { |t| namespaced_constant?(t) }
    .reject { |t| allow_list.include?(t) }
    .uniq
    .filter_map do |t|
      state = resolution(t, index)
      [t, state] if state == :miss || state == :short
    end
end

def unresolved_in(text, index)
  classified_in(text, index).select { |(_, state)| state == :miss }.map(&:first)
end

def elsewhere_in(text, index)
  classified_in(text, index).select { |(_, state)| state == :short }.map(&:first)
end

def doc_path?(path)
  rel = path.sub(%r{\A#{Regexp.escape(project_root)}/?}, "")
  rel == "CLAUDE.md" || rel.start_with?("docs/") || rel.start_with?(".claude/rules/")
end

def run_hook(payload)
  tool = payload["tool_name"]
  input = payload["tool_input"] || {}
  path = input["file_path"].to_s
  return 0 unless File.extname(path) == ".md" && doc_path?(path)

  text =
    case tool
    when "Write" then input["content"].to_s
    when "Edit" then input["new_string"].to_s
    when "MultiEdit" then (input["edits"] || []).map { |e| e["new_string"] }.join("\n")
    else ""
    end
  return 0 if text.empty?

  index = DocSync::CodeIndex.build(project_root)
  elsewhere = elsewhere_in(text, index)
  unless elsewhere.empty?
    warn <<~MSG
      Doc reference check: #{File.basename(path)} names #{elsewhere.size} constant(s) that resolve under a DIFFERENT namespace:
      #{elsewhere.map { |m| "    `#{m}`" }.join("\n")}
      Confirm the namespace against the code: a moved constant reads as correct here because only its last segment matches.
    MSG
  end

  misses = unresolved_in(text, index)
  return 0 if misses.empty?

  warn <<~MSG
    Doc reference check (flagged after the edit; fix it before moving on): #{File.basename(path)} names #{misses.size} code constant(s) that do not resolve in the repo:
    #{misses.map { |m| "    `#{m}`" }.join("\n")}
    Rename the reference, fix the code, add an external namespace to EXTERNAL_NAMESPACES if a gem provides it, or list a deliberate non-reference in .claude/scripts/documentation/.doc-refs-allow.
  MSG
  2
end

def each_doc_line
  Dir.chdir(project_root) do
    DOC_GLOBS.flat_map { |g| Dir.glob(g) }.uniq.sort.each do |file|
      File.readlines(file).each_with_index { |line, i| yield(file, i + 1, line) }
    end
  end
end

def run_full
  index = DocSync::CodeIndex.build(project_root)
  misses = []
  elsewhere = []
  each_doc_line do |file, lineno, line|
    unresolved_in(line, index).each { |tok| misses << "#{file}:#{lineno}  `#{tok}`" }
    elsewhere_in(line, index).each { |tok| elsewhere << "#{file}:#{lineno}  `#{tok}`" }
  end

  unless elsewhere.empty?
    puts "Resolves under a DIFFERENT namespace (warning, not a failure) - confirm each against the code:"
    elsewhere.each { |l| puts "  #{l}" }
    puts
  end

  unless misses.empty?
    misses.each { |l| puts l }
    warn "\n#{misses.size} unresolved doc->code reference(s). Fix them, extend EXTERNAL_NAMESPACES, or list a deliberate one in .doc-refs-allow."
    return 1
  end
  puts "All namespaced doc references resolve."
  0
end

# Every allow-list entry the doc corpus no longer names. The registry is only
# trustworthy while it is pruned.
def run_unused
  seen = Set.new
  each_doc_line do |_file, _lineno, line|
    doc_tokens(line).each { |t| seen << t if allow_list.include?(t) }
  end
  dead = (allow_list - seen).sort

  if dead.empty?
    puts "Every .doc-refs-allow entry is still referenced."
    return 0
  end

  puts "Unused .doc-refs-allow entries (no reference, backticked or in an anchor, anywhere in the doc corpus):"
  dead.each { |t| puts "  #{t}" }
  puts "\nDelete these lines unless a doc is about to name them again."
  0
end

if __FILE__ == $PROGRAM_NAME
  exit run_unused if ARGV.include?("--unused")

  raw = if ARGV.include?("--all")
    ""
  else
    $stdin.tty? ? "" : $stdin.read.to_s
  end
  code =
    if raw.strip.empty?
      run_full
    else
      payload = begin
        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end
      payload ? run_hook(payload) : run_full
    end
  exit code
end
