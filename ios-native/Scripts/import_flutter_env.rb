#!/usr/bin/env ruby

require "pathname"
require "xcodeproj"

root = Pathname.new(__dir__).parent.expand_path
source = root.parent.join("app", ".env")
destination = root.join("Config", "Secrets.plist")

abort "Missing #{source}" unless source.exist?

values = source.each_line.each_with_object({}) do |line, result|
  stripped = line.strip
  next if stripped.empty? || stripped.start_with?("#")

  key, value = stripped.split("=", 2)
  next unless key && value

  result[key.strip] = value.strip.gsub(/\A[\"']|[\"']\z/, "")
end

required = %w[SUPABASE_URL SUPABASE_ANON_KEY]
missing = required.reject { |key| values[key] && !values[key].empty? }
abort "Missing required keys: #{missing.join(', ')}" unless missing.empty?

Xcodeproj::Plist.write_to_path(values.slice(*required), destination.to_s)
File.chmod(0o600, destination)
puts "Created local ignored Config/Secrets.plist without printing credentials."
