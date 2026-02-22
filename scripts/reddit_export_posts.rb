#!/usr/bin/env ruby
# frozen_string_literal: true

# Export your Reddit posts from a subreddit as Jekyll posts with front matter.
# Uses Reddit's public JSON API (no auth). Be polite: one request per 2s when paginating.

require "cgi"
require "json"
require "net/http"
require "time"
require "uri"

BASE = "https://www.reddit.com"
USER_AGENT = "reddit-export/1.0 (one-off export script)"

def fetch_listing(subreddit, username, after = nil)
  path = "/r/#{subreddit}/search.json"
  params = "q=author:#{username}&restrict_sr=on&sort=new&type=link"
  params += "&after=#{after}" if after
  uri = URI("#{BASE}#{path}?#{params}")
  req = Net::HTTP::Get.new(uri)
  req["User-Agent"] = USER_AGENT
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  raise "HTTP #{res.code} #{res.message}" if res.code != "200"
  JSON.parse(res.body)
end

# Re-fetch a single post by permalink (e.g. /r/foo/comments/abc123/title/) to get full selftext.
# The search listing sometimes returns empty selftext for link posts; the comments endpoint has the post.
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

def unescape_body(text)
  return "" if text.nil? || !text.is_a?(String)
  CGI.unescape_html(text)
end

def slugify(title)
  return "untitled" if title.nil? || title.strip.empty?
  s = title.downcase.strip
  s = s.gsub(/[^a-z0-9\s-]/, "").gsub(/\s+/, "-").gsub(/-+/, "-")
  s = s[0, 60].sub(/-+\z/, "") if s.length > 60
  s.empty? ? "untitled" : s
end

def front_matter(title, date_str, subreddit)
  # Quote title for YAML when it contains : or ' or newlines
  title_yaml = (title =~ /[:'"\n]/) ? title.inspect : title
  <<~YAML
    ---
    title: #{title_yaml}
    layout: post
    date: #{date_str}
    categories:
        - Source/Reddit
        - Subreddit/r/#{subreddit}
    ---
  YAML
end

def run(subreddit, username, out_dir = nil)
  out_dir = out_dir || "_posts"
  Dir.mkdir(out_dir) unless Dir.exist?(out_dir)
  written = 0
  after = nil
  used_slugs = {} # date => Set of slugs used, to avoid collisions

  loop do
    begin
      data = fetch_listing(subreddit, username, after)
    rescue => e
      warn "Request failed: #{e.message}"
      warn "Rate limited? Wait a minute and try again." if e.message.include?("429")
      exit 1
    end

    children = data.dig("data", "children") || []
    break if children.empty?

    children.each do |child|
      post = child["data"] || {}
      title = unescape_body(post["title"]) || "Untitled"
      selftext = post["selftext"] || ""
      permalink = post["permalink"] || ""
      if selftext.empty? && !permalink.empty?
        sleep 2
        refetched = fetch_post_by_permalink(permalink)
        selftext = refetched if refetched.is_a?(String) && !refetched.strip.empty?
      end
      created_utc = post["created_utc"]&.to_i
      date_str = created_utc ? Time.at(created_utc).utc.strftime("%Y-%m-%d") : Time.now.utc.strftime("%Y-%m-%d")
      link = permalink.empty? ? "" : "#{BASE}#{permalink}"
      edit_link = permalink.empty? ? "" : "#{BASE}#{permalink.sub(%r{/+$}, '')}/edit"

      base_slug = slugify(title)
      used_slugs[date_str] ||= []
      slug = base_slug
      n = 1
      while used_slugs[date_str].include?(slug)
        n += 1
        slug = "#{base_slug}-#{n}"
      end
      used_slugs[date_str] << slug

      filename = "#{date_str}-#{slug}.md"
      path = File.join(out_dir, filename)

      fm = front_matter(title, date_str, subreddit)
      if selftext.empty?
        body = edit_link.empty? ? "(no text body)" : "_Body not returned by API. [Edit this post on Reddit](#{edit_link}) to copy the markdown and paste it here._"
      else
        body = unescape_body(selftext)
      end
      body += "\n\nOriginally posted on [r/#{subreddit}](#{link})." unless link.empty?
      content = fm.strip + "\n\n" + body

      File.write(path, content)
      written += 1
      puts "  #{filename}"
    end

    after = data.dig("data", "after")
    break unless after
    sleep 2
  end

  puts "Wrote #{written} posts to #{out_dir}/"
end

def main
  abort "Usage: #{$PROGRAM_NAME} SUBREDDIT USERNAME [-o OUTPUT_DIR]" if ARGV.length < 2
  subreddit = ARGV[0]
  username = ARGV[1]
  out_dir = nil
  i = 2
  while i < ARGV.length
    if ARGV[i] == "-o" || ARGV[i] == "--output"
      out_dir = ARGV[i + 1]
      i += 2
    else
      i += 1
    end
  end
  run(subreddit, username, out_dir)
end

main if __FILE__ == $PROGRAM_NAME
