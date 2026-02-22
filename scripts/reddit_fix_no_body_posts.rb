#!/usr/bin/env ruby
# frozen_string_literal: true

# Find Reddit-exported posts in _posts that have "(no text body)" and re-fetch
# each from Reddit's API. If the post has selftext, replace the placeholder.

require "cgi"
require "json"
require "net/http"
require "uri"

BASE = "https://www.reddit.com"
USER_AGENT = "reddit-export/1.0 (one-off export script)"

def fetch_post_by_permalink(permalink)
  return nil if permalink.nil? || permalink.strip.empty?
  path = permalink.end_with?("/") ? "#{permalink}.json" : "#{permalink}/.json"
  uri = URI("#{BASE}#{path}")
  req = Net::HTTP::Get.new(uri)
  req["User-Agent"] = USER_AGENT
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  return nil if res.code != "200"
  data = JSON.parse(res.body)
  post_list = data.is_a?(Array) && data[0] ? data[0].dig("data", "children") : nil
  return nil unless post_list && post_list[0]
  post_list[0].dig("data", "selftext")
rescue => _
  nil
end

def extract_reddit_permalink(content)
  # Match: Originally posted on [r/...](https://www.reddit.com/r/.../comments/.../.../).
  m = content.match(%r!Originally posted on \[r/[^\]]+\]\((https://www\.reddit\.com/r/[^)]+)\)!m)
  return nil unless m
  url = m[1]
  # Strip trailing slash for consistency; permalink is path only
  path = URI(url).path
  path.end_with?("/") ? path.chop : path
end

def edit_url_from_permalink(permalink)
  return "" if permalink.nil? || permalink.strip.empty?
  "#{BASE}#{permalink.sub(%r{/+$}, '')}/edit"
end

def run(posts_dir = "_posts")
  posts_dir = posts_dir.sub(%r{/+$}, "")
  dir = File.expand_path(posts_dir)
  unless Dir.exist?(dir)
    warn "Directory not found: #{dir}"
    exit 1
  end

  no_body = Dir.glob(File.join(dir, "*.md")).select do |path|
    content = File.read(path)
    content.include?("Source/Reddit") && (content.include?("(no text body)") || content.include?("Body not returned by API"))
  end

  if no_body.empty?
    puts "No Reddit posts with '(no text body)' found in #{posts_dir}."
    return
  end

  puts "Found #{no_body.size} post(s) with no body. Re-fetching from Reddit..."
  fixed = 0
  no_body.each do |path|
    content = File.read(path)
    permalink = extract_reddit_permalink(content)
    unless permalink
      warn "  #{File.basename(path)}: no Reddit URL found"
      next
    end
    sleep 2
    selftext = fetch_post_by_permalink(permalink)
    if selftext.is_a?(String) && !selftext.strip.empty?
      body = CGI.unescape_html(selftext.strip)
      # Replace either placeholder with the fetched body (keep trailing "Originally posted on..." as-is)
      new_content = content
        .sub(/_Body not returned by API\. \[Edit[^]]+\]\([^)]+\) to copy the markdown and paste it here\._/m, body)
        .sub("(no text body)", body)
      File.write(path, new_content)
      puts "  Updated: #{File.basename(path)}"
      fixed += 1
    else
      # Still no body: ensure file has edit link so user can copy-paste markdown
      edit_url = edit_url_from_permalink(permalink)
      placeholder = edit_url.empty? ? "(no text body)" : "_Body not returned by API. [Edit this post on Reddit](#{edit_url}) to copy the markdown and paste it here._"
      new_content = content.sub("(no text body)", placeholder)
      unless new_content == content
        File.write(path, new_content)
        puts "  Added edit link: #{File.basename(path)}"
      end
      puts "  No body from API: #{File.basename(path)} (open edit link to copy markdown)" if edit_url.empty? || new_content == content
    end
  end
  puts "Done. Updated #{fixed} of #{no_body.size} posts."
end

def main
  posts_dir = ARGV[0] || "_posts"
  run(posts_dir)
end

main if __FILE__ == $PROGRAM_NAME
