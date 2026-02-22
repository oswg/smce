#!/usr/bin/env ruby
# frozen_string_literal: true

# Add "<!-- more -->" after the 2nd paragraph in posts that have more than 3
# paragraphs and don't already have the tag.

def extract_body(content)
  return nil unless content =~ /\A---\s*\n.*?\n---\s*\n/m
  content.sub(/\A---\s*\n.*?\n---\s*\n/m, "")
end

def insert_more_after_second_paragraph(body)
  blocks = body.split(/\n\n+/)
  non_empty_indices = blocks.each_index.reject { |i| blocks[i].strip.empty? }
  return body if non_empty_indices.size <= 3
  second_idx = non_empty_indices[1]
  before = blocks[0..second_idx].join("\n\n")
  after = blocks[(second_idx + 1)..].join("\n\n")
  before + "\n\n<!-- more -->\n\n" + after
end

def post_title(content)
  m = content.match(/^title:\s*(.+)$/m)
  m ? m[1].strip.gsub(/\A["']|["']\z/, "") : nil
end

def process(path)
  content = File.read(path)
  return [0, nil] if content.include?("<!-- more -->")
  body = extract_body(content)
  return [0, nil] unless body
  new_body = insert_more_after_second_paragraph(body)
  return [0, nil] if new_body == body
  front_matter = content.match(/\A---\s*\n.*?\n---\s*\n/m)[0]
  File.write(path, front_matter + new_body)
  title = post_title(content) || File.basename(path)
  [1, title]
end

posts_dir = File.expand_path(ARGV[0] || "_posts")
count = 0
Dir.glob(File.join(posts_dir, "*.{md,markdown}")).each do |path|
  n, name = process(path)
  if n == 1
    count += 1
    puts name
  end
end
puts "Added <!-- more --> to #{count} post(s)." if count > 0
