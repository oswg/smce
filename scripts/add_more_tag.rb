#!/usr/bin/env ruby
# frozen_string_literal: true

# Add "<!-- more -->" for posts that don't have it:
# - If there is a blockquote: put the tag between the last intro paragraph and the
#   first blockquote, unless there are >2 intro paragraphs — then put it between
#   the second and third intro paragraph.
# - If there is no blockquote: put after 2nd paragraph only when there are >3 blocks.

def extract_body(content)
  return nil unless content =~ /\A---\s*\n.*?\n---\s*\n/m
  content.sub(/\A---\s*\n.*?\n---\s*\n/m, "")
end

def blockquote?(block)
  block.strip.start_with?(">")
end

def insert_more_tag(body)
  blocks = body.split(/\n\n+/)
  first_bq_idx = blocks.index { |b| blockquote?(b) }

  if first_bq_idx.nil?
    # No blockquote: only add if >3 blocks, after 2nd paragraph
    non_empty = blocks.each_index.reject { |i| blocks[i].strip.empty? }
    return body if non_empty.size <= 3
    second_idx = non_empty[1]
    before = blocks[0..second_idx].join("\n\n")
    after = blocks[(second_idx + 1)..].join("\n\n")
    return before + "\n\n<!-- more -->\n\n" + after
  end

  intro_non_empty = (0...first_bq_idx).reject { |i| blocks[i].strip.empty? }
  n_intro = intro_non_empty.size

  if n_intro > 2
    # Between second and third intro paragraph
    second_intro_idx = intro_non_empty[1]
    before = blocks[0..second_intro_idx].join("\n\n")
    after = blocks[(second_intro_idx + 1)..].join("\n\n")
  else
    # Between last intro paragraph and first blockquote
    last_intro_idx = first_bq_idx - 1
    before = blocks[0..last_intro_idx].join("\n\n")
    after = blocks[first_bq_idx..].join("\n\n")
  end

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
  new_body = insert_more_tag(body)
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
