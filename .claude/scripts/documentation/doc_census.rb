#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

# Finds DERIVABLE facts in the docs: a number a command answers (a count of
# errors, settings, hooks, specs, examples; a gem version copied from a lockfile;
# a measured duration). The doc names the SOURCE instead. A genuine CONTRACT
# number goes in .claude/scripts/documentation/.doc-census-allow under a reason.
# Rule: .claude/rules/docs.md. Plain `ruby`, no bundle.
#
# The scan reports at most ONE hit per line (the first pattern that matches), so
# a line fixed for one shape can surface again under another: re-run it after
# every rewrite. Fenced code blocks are skipped.

DOC_GLOBS = %w[docs/**/*.md .claude/rules/*.md CLAUDE.md].freeze
EXEMPT_FILES = %w[.claude/rules/docs.md].freeze
VERSION_LEDGERS = %w[docs/upstream.md].freeze

ORDINALS = %w[second third fourth fifth sixth].freeze

CENSUS_NOUNS = %w[
  tables? models? controllers? files? specs? columns? classes jobs? services?
  settings? hooks? error\ classes errors? warnings? failures? offenses? examples? lines?
  policies migrations? generators? gems? packages? call.sites? occurrences?
  rake\ tasks? locales? hosts? methods? exemptions?
].freeze

INVENTORY_NOUNS = %w[
  error\ classes errors settings hooks spec\ files specs models generators migrations call\ sites
].freeze

NOUN_RE = "(?:#{CENSUS_NOUNS.join("|")})"
INVENTORY_RE = "(?:#{INVENTORY_NOUNS.join("|")})"
COUNT_WORDS = %w[four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty].freeze
WORD_NOUNS = %w[errors settings hooks examples specs files models columns tables generators migrations policies].freeze

PATTERNS = {
  "digit count of code artifacts" => /(?<![:.+\d§])(?<!RFC )(?<!\d\.)\b\d+\s+(?:[a-z-]+\s+)?#{NOUN_RE}\b/i,
  "definite count of an inventory (\"the two settings\")" => /\b(?:the|all|both|its|those)\s+(?:two|three|four|five|six|seven|eight|nine|ten)\s+#{INVENTORY_RE}\b/i,
  "ordinal narration (\"when adding the second X\")" => /\b(?:when|once|after|before|until)\s+(?:adding|there\s+is|there\s+are|we\s+add|you\s+add)\s+(?:a|the)\s+(?:#{ORDINALS.join("|")})\b/i,
  "word count of an enumerated inventory (\"twelve errors\")" => /\b(?:#{COUNT_WORDS.join("|")})\s+(?:[a-z-]+\s+)?(?:#{WORD_NOUNS.join("|")})\b/i,
  "three-part version (a lockfile copy)" => /(?<![\d.§])\d+\.\d+\.\d+(?!\d|\.\d)/,
  "two-part library version" => /\b(?:RSpec|Rails|Ruby|Pundit|Combustion|Zeitwerk|SQLite|Standard|Bundler)\s+v?\d+\.\d+(?:\.x)?\b/,
  "measured duration" => /(?:~|about|around|roughly|takes|took|runs\s+in|finishes\s+in)\s*\d+\s*(?:-|\s)?(?:min(?:ute)?s?|ms|µs|seconds?)\b/i,
  "measured count of errors" => /\b\d+\s+(?:type\s+)?(?:errors|warnings|failures|offenses)\b/i
}.freeze

HTTP_STATUS_RE = /\A[1-5]\d\d\s/

def project_root
  ENV["CLAUDE_PROJECT_DIR"] || Dir.pwd
end

def allow_list
  @allow_list ||= begin
    file = File.join(project_root, ".claude", "scripts", "documentation", ".doc-census-allow")
    if File.file?(file)
      File.readlines(file).map(&:strip).reject { |l| l.empty? || l.start_with?("#") }
    else
      []
    end
  end
end

def allowed?(line)
  allow_list.any? { |entry| line.include?(entry) }
end

def doc_files
  Dir.chdir(project_root) do
    DOC_GLOBS.flat_map { |g| Dir.glob(g) }.uniq.sort.reject { |f| EXEMPT_FILES.include?(f) }
  end
end

def scan
  hits = []
  doc_files.each do |file|
    in_fence = false
    File.foreach(File.join(project_root, file)).with_index(1) do |line, number|
      in_fence = !in_fence if line.lstrip.start_with?("```")
      next if in_fence || allowed?(line)

      PATTERNS.each do |kind, re|
        next if kind.include?("version") && VERSION_LEDGERS.include?(file)

        match = line.match(re) or next
        next if HTTP_STATUS_RE.match?(match[0])

        hits << {file: file, line: number, kind: kind, match: match[0].strip, text: line.strip}
        break
      end
    end
  end
  hits
end

hits = scan

if ARGV.include?("--json")
  puts JSON.pretty_generate(hits)
elsif hits.empty?
  puts "doc_census: no derivable facts found."
else
  puts "doc_census: #{hits.size} derivable fact(s) in the docs - replace each with timeless language or the source that answers it; allow-list a contract number in .doc-census-allow:"
  hits.group_by { |h| h[:kind] }.each do |kind, group|
    puts "\n## #{kind} (#{group.size})"
    group.each { |h| puts "  #{h[:file]}:#{h[:line]}  [#{h[:match]}]  #{h[:text][0, 140]}" }
  end
end

exit(hits.empty? ? 0 : 1)
