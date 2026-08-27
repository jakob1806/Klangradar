#!/usr/bin/env ruby
# Mirrors ios-native/Scripts/import_flutter_env.rb: reads the already
# configured Flutter app/.env and writes android-native/local.properties
# (gitignored) so the Android app uses the same live Supabase project
# without ever printing the credentials to the terminal.

require "pathname"

root = Pathname.new(__dir__).parent.expand_path
source = root.parent.join("app", ".env")
destination = root.join("local.properties")

abort "Missing #{source}" unless source.exist?

values = source.each_line.each_with_object({}) do |line, result|
  stripped = line.strip
  next if stripped.empty? || stripped.start_with?("#")

  key, value = stripped.split("=", 2)
  next unless key && value

  result[key.strip] = value.strip.gsub(/\A["']|["']\z/, "")
end

required = %w[SUPABASE_URL SUPABASE_ANON_KEY]
missing = required.reject { |key| values[key] && !values[key].empty? }
abort "Missing required keys in #{source}: #{missing.join(', ')}" unless missing.empty?
if values["SUPABASE_URL"].include?("your-project")
  abort "#{source} still has placeholder values — fill in the real Supabase project first."
end

existing = destination.exist? ? destination.read : ""
sdk_line = existing.lines.find { |line| line.start_with?("sdk.dir=") }

lines = []
lines << sdk_line if sdk_line
lines << "SUPABASE_URL=#{values['SUPABASE_URL']}\n"
lines << "SUPABASE_ANON_KEY=#{values['SUPABASE_ANON_KEY']}\n"

destination.write(lines.join)
File.chmod(0o600, destination.to_s)
puts "Wrote local.properties (kept existing sdk.dir line, if any) without printing credentials."
