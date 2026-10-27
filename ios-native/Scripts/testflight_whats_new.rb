#!/usr/bin/env ruby
# Erstellt von Claude Code (Nutzerwunsch 27.10.2026): setzt den TestFlight-
# Testhinweis ("Was testen?", de-DE) eines hochgeladenen Builds aus
# KlangradarNative/Resources/WhatsNew.json – derselbe Text, den die App als
# "Neu in Klangradar" zeigt. Wartet, bis App Store Connect den Build kennt.
#
#   ruby Scripts/testflight_whats_new.rb <BUILD_NUMBER>   (DRY_RUN=1: nur lesen)
# Erwartet ~/.appstoreconnect/config (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH).
require "json"
require "net/http"
require "openssl"
require "base64"

BUILD = ARGV[0] or abort("Build-Nummer fehlt")
BUNDLE_ID = "de.klangradar.native"
config = File.read(File.expand_path("~/.appstoreconnect/config")).scan(/^(\w+)=(.*)$/).to_h
config.transform_values! { |v| v.strip.delete('"').gsub("$HOME", Dir.home) }
KEY = OpenSSL::PKey::EC.new(File.read(config.fetch("ASC_KEY_PATH")))
KEY_ID = config.fetch("ASC_KEY_ID")
ISSUER = config.fetch("ASC_ISSUER_ID")

notes = JSON.parse(File.read(File.join(__dir__, "..", "KlangradarNative", "Resources", "WhatsNew.json")))
intro = notes["intro"] ? [notes["intro"], ""] : []
text = ([notes["title"], ""] + intro + notes["sections"].flat_map { |s| [s["title"]] + s["items"] + [""] }).join("\n").strip[0, 4000]

def b64(data) = Base64.urlsafe_encode64(data, padding: false)

def token
  header = b64({ alg: "ES256", kid: KEY_ID, typ: "JWT" }.to_json)
  payload = b64({ iss: ISSUER, iat: Time.now.to_i, exp: Time.now.to_i + 900, aud: "appstoreconnect-v1" }.to_json)
  der = KEY.sign(OpenSSL::Digest::SHA256.new, "#{header}.#{payload}")
  r, s = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00")[-32, 32] }
  "#{header}.#{payload}.#{b64(r + s)}"
end

def api(method, path, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  request = Net::HTTP.const_get(method.capitalize).new(uri)
  request["Authorization"] = "Bearer #{token}"
  request["Content-Type"] = "application/json"
  request.body = body.to_json if body
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
  abort("❌ #{method} #{path}: #{response.code} #{response.body[0, 300]}") unless response.code.start_with?("2")
  response.body.to_s.empty? ? {} : JSON.parse(response.body)
end

app = api("GET", "/v1/apps?filter[bundleId]=#{BUNDLE_ID}&limit=1")["data"].first or abort("❌ App #{BUNDLE_ID} nicht gefunden")
build = nil
45.times do
  build = api("GET", "/v1/builds?filter[app]=#{app['id']}&filter[version]=#{BUILD}&limit=1")["data"].first
  break if build
  sleep 60
end
abort("❌ Build #{BUILD} nach 45 Min. noch nicht in App Store Connect") unless build

existing = api("GET", "/v1/builds/#{build['id']}/betaBuildLocalizations")["data"].find { |l| l.dig("attributes", "locale") == "de-DE" }
if ENV["DRY_RUN"] == "1"
  puts "Build #{BUILD} gefunden (#{build['id']}), vorhandener Hinweis: #{existing&.dig('attributes', 'whatsNew').inspect}"
  puts "--- würde setzen ---\n#{text}"
  exit
end
if existing
  api("PATCH", "/v1/betaBuildLocalizations/#{existing['id']}", { data: { type: "betaBuildLocalizations", id: existing["id"], attributes: { whatsNew: text } } })
else
  api("POST", "/v1/betaBuildLocalizations", { data: { type: "betaBuildLocalizations", attributes: { locale: "de-DE", whatsNew: text },
                                                     relationships: { build: { data: { type: "builds", id: build["id"] } } } } })
end
puts "✅ TestFlight-Testhinweis für Build #{BUILD} gesetzt (#{notes['id']})."
