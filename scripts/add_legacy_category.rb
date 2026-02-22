#!/usr/bin/env ruby
# frozen_string_literal: true

# Add category "Meta/Legacy" to all posts older than the welcome post (date 2026-02-14).

WELCOME_CUTOFF = "2026-02-14"
LEGACY_CATEGORY = "Meta/Legacy"

def post_date(content, filename)
  m = content.match(/^date:\s*(\d{4}-\d{2}-\d{2})/m)
  return m[1] if m
  # From filename like 2026-02-08-welcome-to-smce.markdown
  m2 = filename.match(/^(\d{4}-\d{2}-\d{2})/)
  m2 ? m2[1] : nil
end

def already_has_legacy?(content)
  content.include?(LEGACY_CATEGORY)
end

def add_legacy_to_categories(content)
  # Already has it
  return content if content.include?(LEGACY_CATEGORY)

  # Empty categories: "categories:\n\n" or "categories: \n\n" or "categories:\n  \n"
  if content =~ /^categories:\s*\n\s*\n/m
    return content.sub(/^(categories:\s*)\n\s*\n/m, "\\1\n  - #{LEGACY_CATEGORY}\n\n")
  end

  # Categories with list: add before the next top-level key (e.g. excerpt: or ---)
  # Match "categories:" and then lines that are list items (start with spaces + -)
  if content =~ /^categories:\s*\n((?:\s+-\s+.+\n)+)/m
    return content.sub(/^(categories:\s*\n(?:\s+-\s+.+\n)+)/m, "\\1  - #{LEGACY_CATEGORY}\n")
  end

  content
end

def run(posts_dir = "_posts")
  dir = File.expand_path(posts_dir)
  Dir.glob(File.join(dir, "*.{md,markdown}")).each do |path|
    filename = File.basename(path)
    content = File.read(path)
    date_str = post_date(content, filename)
    next unless date_str
    next if date_str >= WELCOME_CUTOFF
    next if already_has_legacy?(content)
    new_content = add_legacy_to_categories(content)
    next if new_content == content
    File.write(path, new_content)
    puts "  #{filename}"
  end
end

run(ARGV[0] || "_posts")
