#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

# PostToolUse hook (Edit|MultiEdit|Write): flags run / session / timeline
# narration in the markdown that .claude/rules/docs.md governs, i.e. every .md
# under docs/ and .claude/rules/. Code comments are out of scope in this repo.
# It runs AFTER the edit, so it cannot stop it: exit 2 with a stderr message
# naming file, line and the banned pattern makes the agent fix the line before
# moving on; exit 0 for any other path or a clean edit. Plain `ruby`, no bundle.
#
# Scope: paths resolve against CLAUDE_PROJECT_DIR, so an edit made inside a
# sibling worktree (../tenancy_dable-wt/*) is not checked; run doc_census.rb and
# check_doc_refs.rb --all there, and read the diff against docs.md.
#
# The pattern list is not exhaustive: a phrasing it does not match is still
# banned by .claude/rules/docs.md. It aims at low false positives, so it skips
# fenced code blocks and inline `code` spans, and matches finding ids only in a
# run-id-looking context.

EXEMPT = %w[.claude/rules/docs.md docs/upstream.md].freeze
SCOPES = %w[docs/ .claude/rules/].freeze

FINDING_ID_NO_S3 = "(?:[FBLN]\\d{1,2}|S(?!3\\b)\\d{1,2})"

# [label, regexp]. Matched against a line with inline `code` spans removed.
PATTERNS = [
  ["run/phase id (\"phase 3\")", /\bphases?[-_ ]?\d/i],
  ["workstream id (\"W2\")", /\bW\d{1,2}\b/],
  ["finding id in parentheses (\"(F7)\")", /[(\[]\s*#{FINDING_ID_NO_S3}(?:\s*[,\/+&]\s*#{FINDING_ID_NO_S3})*\s*[)\]]/],
  ["finding id after a run word (\"finding F7\")", /\b(?i:findings?|items?|proposals?|fix|bug|blocker|residual|nit|issue|per|see)\s+#{FINDING_ID_NO_S3}\b/],
  ["finding id list (\"F7/F8\")", /\b#{FINDING_ID_NO_S3}\s*(?:\/|,|\+|&|and)\s*#{FINDING_ID_NO_S3}\b/],
  ["\"fix round\"", /\bfix[- ]rounds?\b/i],
  ["red team as a finding source", /\bred[- ]?team\s+(?:found|flagged|reported|showed|proved|round|run|pass|review|finding)|\b(?:by|after|from|per)\s+the\s+red[- ]?team\b/i],
  ["\"this release\" / \"this PR\"", /\bthis\s+(?:release|PR|pull request|ticket)\b/i],
  ["session trace (\"nesta sessao\", \"in this session\")", /\b(?:nesta|nessa|na)\s+(?:sess[aã]o|conversa|reuni[aã]o)\b|\bin\s+this\s+(?:session|conversation)\b/i],
  ["conversation trace (\"as discussed\")", /\bas\s+discussed\b|\bper\s+(?:our\s+)?discussion\b|\bper\s+the\s+(?:review|audit)\b|\bafter\s+(?:the\s+)?(?:review|feedback)\b|\bconforme\s+(?:discutido|combinado|alinhado|conversado)\b/i],
  ["person (an acting role)", /\bthe\s+(?:maintainer|owner|author|reviewer|user)\s+(?:asked|decided|wanted|chose|approved|requested|said)\b/i],
  ["date stamp", /\b20\d\d-[01]\d-[0-3]\d\b/],
  ["\"since vX.Y\"", /\bsince\s+(?:version\s+)?v?\d+\.\d+/i],
  ["version-of-origin narration (\"added in 0.5.0\")", /\b(?:added|introduced|removed|changed|renamed|fixed)\s+(?:in|by|with)\s+(?:version\s+)?v?\d+\.\d+/i],
  ["\"formerly\" / \"as of\"", /\b(?:formerly|as of)\b|\banteriormente\b|\bantigamente\b/i],
  ["tracker reference", /\b(?:PR|pull request|issue|ticket)\s*#\d+|\bGH-\d+|\bproposals?\s+(?:item\s+)?\d+\b|\buntil\b[^.]{0,40}\blands?\b|\btracked\s+in\b/i]
].freeze

def parsed_input
  raw = $stdin.read.to_s
  return nil if raw.strip.empty?

  JSON.parse(raw)
rescue JSON::ParserError
  nil
end

def strip_inline_code(line)
  line.gsub(/`[^`\n]*`/, "``")
end

def fence?(line)
  line.lstrip.start_with?("```", "~~~")
end

# Fence state at the start of `needle` inside the file as it is on disk
# (PostToolUse: the edit is already applied). Falls back to "not in a fence".
def fence_state_at(file_text, needle)
  return false if file_text.nil? || needle.to_s.empty?

  at = file_text.index(needle)
  return false unless at

  file_text[0, at].lines.count { |l| fence?(l) }.odd?
end

def line_offset(file_text, needle)
  return 0 if file_text.nil? || needle.to_s.empty?

  at = file_text.index(needle)
  at ? file_text[0, at].count("\n") : 0
end

# Multiset difference on stripped lines: a line already present in the old text
# is not "added", so re-saving a file does not re-flag untouched lines.
def added(old_text, new_text, file_text)
  seen = Hash.new(0)
  old_text.to_s.lines.each { |l| seen[l.strip] += 1 }

  in_fence = fence_state_at(file_text, new_text)
  base = line_offset(file_text, new_text)
  out = []
  new_text.to_s.lines.each_with_index do |line, i|
    stripped = line.strip
    if fence?(line)
      in_fence = !in_fence
      next
    end
    next if in_fence || stripped.empty?

    if seen[stripped].positive?
      seen[stripped] -= 1
      next
    end
    out << [base + i + 1, stripped]
  end
  out
end

def violations(lines)
  lines.flat_map do |lineno, text|
    plain = strip_inline_code(text)
    PATTERNS.filter_map do |label, re|
      m = plain.match(re) or next
      [lineno, label, m[0], text]
    end
  end
end

data = parsed_input
exit 0 if data.nil?

tool_input = data["tool_input"] || {}
path = tool_input["file_path"].to_s
exit 0 if path.empty? || File.extname(path) != ".md"

project_dir = File.expand_path(ENV["CLAUDE_PROJECT_DIR"] || Dir.pwd)
absolute = File.expand_path(path, project_dir)
exit 0 unless absolute.start_with?(project_dir + File::SEPARATOR)

relative = absolute.delete_prefix(project_dir + File::SEPARATOR)
exit 0 unless SCOPES.any? { |s| relative.start_with?(s) }
exit 0 if EXEMPT.include?(relative)

file_text = File.file?(absolute) ? File.read(absolute) : nil

pairs =
  case data["tool_name"]
  when "Edit" then [[tool_input["old_string"], tool_input["new_string"]]]
  when "MultiEdit" then (tool_input["edits"] || []).map { |e| [e["old_string"], e["new_string"]] }
  when "Write" then [["", tool_input["content"]]]
  else []
  end
exit 0 if pairs.empty?

# A Write has the whole file as its text, so line numbers are file lines.
found = pairs.flat_map do |old_text, new_text|
  violations(added(old_text, new_text, (data["tool_name"] == "Write") ? nil : file_text))
end
exit 0 if found.empty?

lines = found.first(8).map do |lineno, label, match, text|
  "    #{relative}:#{lineno}  [#{label}]  matched \"#{match}\"\n      #{text[0, 120]}"
end

warn <<~MSG
  Docs policy (.claude/rules/docs.md): #{relative} adds run, session or timeline narration, which docs never carry (the edit is already on disk: fix the line before moving on).
  Docs describe the gem as it is: if a sentence answers "what happened / who wanted it / when", delete it or rewrite it as present-tense behaviour with its rationale in system terms. History lives in git, CHANGELOG.md and the DESIGN.md deltas.
  #{lines.join("\n")}
MSG
exit 2
