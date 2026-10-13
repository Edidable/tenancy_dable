#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

# Rule <-> hub parity for the knowledge system:
#   - every domain rule .claude/rules/<name>.md has a hub docs/domains/<name>.md
#   - every domain rule carries `paths:` frontmatter (that is what auto-loads it)
#   - every spoke folder docs/domains/<name>/ has its hub, and the hub links each spoke
# A convention rather than a domain (see PROCESS_RULES) has no hub.

PROCESS_RULES = %w[docs].freeze

def project_root
  ENV["CLAUDE_PROJECT_DIR"] || Dir.pwd
end

def rule_names
  Dir.glob(File.join(project_root, ".claude", "rules", "*.md")).map { |f| File.basename(f, ".md") }.sort
end

def hub_names
  Dir.glob(File.join(project_root, "docs", "domains", "*.md")).map { |f| File.basename(f, ".md") }.sort
end

def spoke_folders
  Dir.glob(File.join(project_root, "docs", "domains", "*")).select { |d| File.directory?(d) }.map { |d| File.basename(d) }.sort
end

def rule_has_paths?(name)
  file = File.join(project_root, ".claude", "rules", "#{name}.md")
  head = File.read(file)[/\A---\s*\n(.*?)\n---\s*$/m, 1].to_s
  head.match?(/^paths:\s*(\n\s*-|\[)/)
rescue
  false
end

def unlinked_spokes(hub)
  hub_file = File.join(project_root, "docs", "domains", "#{hub}.md")
  return [] unless File.file?(hub_file)

  text = File.read(hub_file)
  Dir.glob(File.join(project_root, "docs", "domains", hub, "*.md")).sort.filter_map do |spoke|
    base = File.basename(spoke)
    base unless text.include?("#{hub}/#{base}") || text.include?("(#{base})") || text.include?("./#{base}")
  end
end

rules = rule_names
hubs = hub_names

rules_without_hub = rules - hubs - PROCESS_RULES
hubs_without_rule = hubs - rules
misfiled_process_rules = (PROCESS_RULES & rules) & hubs
rules_without_paths = (rules - PROCESS_RULES).reject { |n| rule_has_paths?(n) }
folders_without_hub = spoke_folders - hubs
spokes_unlinked = (spoke_folders & hubs).to_h { |h| [h, unlinked_spokes(h)] }.reject { |_, v| v.empty? }

result = {
  rules_without_hub: rules_without_hub,
  hubs_without_rule: hubs_without_rule,
  process_rules_with_hub: misfiled_process_rules,
  domain_rules_without_paths: rules_without_paths,
  spoke_folders_without_hub: folders_without_hub,
  spokes_not_linked_from_hub: spokes_unlinked
}

failing = !(rules_without_hub.empty? && misfiled_process_rules.empty? && rules_without_paths.empty? &&
  folders_without_hub.empty? && spokes_unlinked.empty?)

if ARGV.include?("--json")
  puts JSON.pretty_generate(result)
else
  rules_without_hub.each do |name|
    puts "doc_parity: .claude/rules/#{name}.md has no docs/domains/#{name}.md - create the hub with that exact name, or dissolve the rule into the domain that owns its facts, or list it in PROCESS_RULES if it is a convention rather than a domain."
  end
  misfiled_process_rules.each do |name|
    puts "doc_parity: #{name} is listed in PROCESS_RULES but docs/domains/#{name}.md exists - remove it from the list."
  end
  rules_without_paths.each do |name|
    puts "doc_parity: .claude/rules/#{name}.md has no `paths:` frontmatter - a domain rule auto-loads only through its paths globs."
  end
  folders_without_hub.each do |name|
    puts "doc_parity: docs/domains/#{name}/ holds spokes but docs/domains/#{name}.md (the hub) does not exist."
  end
  spokes_unlinked.each do |hub, spokes|
    spokes.each { |s| puts "doc_parity: docs/domains/#{hub}/#{s} is not linked from the hub docs/domains/#{hub}.md (## Spokes map) - a spoke the hub does not link will not surface." }
  end
  puts "doc_parity: every domain rule has its hub, its paths and linked spokes." unless failing
  hubs_without_rule.each do |name|
    puts "doc_parity (info): docs/domains/#{name}.md has no .claude/rules/#{name}.md - fine for a reference doc; a domain with code paths should get a rule of the same name carrying paths: frontmatter."
  end
end

exit(failing ? 1 : 0)
