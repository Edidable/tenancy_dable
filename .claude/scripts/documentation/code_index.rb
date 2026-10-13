#!/usr/bin/env ruby
# frozen_string_literal: true

require "set"

# Index of every constant this repo defines, used by check_doc_refs.rb to decide
# whether a namespaced constant a doc names is real. Inside this gem the
# `TenancyDable::*` namespace is IN-repo (it is the code under `lib/`), so a doc
# naming `TenancyDable::Scoped` resolves against `lib/`, not against an external list.
#
# Standalone use (plain `ruby`, no bundle):
#   ruby .claude/scripts/documentation/code_index.rb --list        every indexed constant
#   ruby .claude/scripts/documentation/code_index.rb --uncovered   lib/ constants no doc names
module DocSync
  module CodeIndex
    SCAN_DIRS = %w[lib spec/internal spec/support].freeze
    PUBLIC_DIRS = %w[lib].freeze
    DEF_RE = /^(\s*)(?:class|module)\s+([A-Z]\w*(?:::[A-Z]\w*)*)/
    CONST_ASSIGN_RE = /^(\s*)([A-Z]\w*)\s*=[^=]/

    # A Narrative Anchor, `[LABEL:value]`, on one line. Docs name most constants
    # this way (`[CLASS:TenancyDable::Foo]`, `[MODULE:...]`, `[ERROR:...]`,
    # `[CONST:A::B::C]`), so a scan that read only backticks would be blind to them.
    ANCHOR_RE = /\[([A-Z][A-Z_]*):([^\]\n]+)\]/
    # The namespaced constant an anchor value starts with (`TenancyDable::Audit.run`
    # yields `TenancyDable::Audit`); a value that is not a constant yields nothing.
    ANCHOR_CONSTANT_RE = /\A[A-Z]\w*(?:::[A-Z]\w*)+/

    module_function

    def root
      ENV["CLAUDE_PROJECT_DIR"] || Dir.pwd
    end

    # Every anchor value in `text`, whatever it holds.
    def anchor_values(text)
      text.to_s.scan(ANCHOR_RE).map { |(_label, value)| value.strip }
    end

    # The namespaced constants that anchors in `text` name.
    def anchor_constants(text)
      anchor_values(text).filter_map { |value| value[ANCHOR_CONSTANT_RE] }
    end

    def build(root_dir = root, dirs: SCAN_DIRS)
      short = Set.new
      fqn = Set.new
      top = Set.new
      dirs.each do |dir|
        Dir.glob(File.join(root_dir, dir, "**", "*.rb")).sort.each do |file|
          scan_file(file, short, fqn, top)
        end
      end
      {short: short, fqn: fqn, top: top}
    end

    # The fully-qualified name of a nested declaration is the enclosing
    # `class`/`module` names joined to it, so the scan keeps a stack keyed by
    # indentation: a lexically nested body is always indented further than the
    # declaration that opens it.
    def scan_file(file, short, fqn, top)
      stack = []
      File.foreach(file) do |line|
        if (m = DEF_RE.match(line))
          indent = m[1].length
          stack.pop while stack.any? && stack.last[:indent] >= indent

          name = m[2]
          qualified = (stack.map { |e| e[:name] } + [name]).join("::")
          fqn << qualified
          short << name.split("::").last
          top << qualified.split("::").first
          stack << {indent: indent, name: name}
        elsif (m = CONST_ASSIGN_RE.match(line))
          indent = m[1].length
          enclosing = stack.take_while { |e| e[:indent] < indent }.map { |e| e[:name] }
          name = m[2]
          fqn << (enclosing + [name]).join("::")
          short << name
        end
      end
    rescue
      nil
    end

    # Constants under lib/ that no doc, rule or CLAUDE.md names (by full name or
    # by its last segment, in backticks or inside a Narrative Anchor). A worklist
    # for `/remember sync`, not a gate: a private helper may be consciously
    # undocumented.
    def uncovered(root_dir = root)
      public_fqn = build(root_dir, dirs: PUBLIC_DIRS)[:fqn]
      corpus = Dir.chdir(root_dir) do
        (Dir.glob("docs/**/*.md") + Dir.glob(".claude/rules/*.md") + Dir.glob("CLAUDE.md"))
          .map { |f| File.read(f) }.join("\n")
      end
      ticks = corpus.scan(/`([^`\n]+)`/).flatten + anchor_values(corpus)
      public_fqn.sort.reject do |name|
        last = name.split("::").last
        next true if last == last.upcase # ALL_CAPS constants (VERSION, MESSAGE) are values, not API

        ticks.any? { |t| t.include?(name) || t.match?(/(\A|[^\w])#{Regexp.escape(last)}(\z|[^\w])/) }
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.include?("--list")
    puts DocSync::CodeIndex.build[:fqn].sort
  elsif ARGV.include?("--uncovered")
    list = DocSync::CodeIndex.uncovered
    if list.empty?
      puts "code_index: every constant under lib/ is named by a doc or a rule."
    else
      puts "code_index: constants under lib/ that no doc, rule or CLAUDE.md names (document each in its domain hub, or skip it consciously):"
      list.each { |n| puts "  #{n}" }
    end
  else
    warn "usage: code_index.rb --list | --uncovered"
    exit 64
  end
end
