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
# Nutzerwunsch 29.10.2026: Mail zu neuen Builds nur noch an diese Adresse.
# Apples automatische Tester-Benachrichtigung wird je Build abgeschaltet,
# stattdessen schickt Mail.app auf diesem Mac eine Nachricht hierher.
NOTIFY_EMAIL = "jakob.liess@outlook.de"
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

unless ENV["DRY_RUN"] == "1"
  # So früh wie möglich (noch während der Verarbeitung), damit Apple die
  # Tester gar nicht erst benachrichtigt.
  detail = api("GET", "/v1/builds/#{build['id']}/buildBetaDetail")["data"]
  if detail && detail.dig("attributes", "autoNotifyEnabled") != false
    api("PATCH", "/v1/buildBetaDetails/#{detail['id']}", { data: { type: "buildBetaDetails", id: detail["id"], attributes: { autoNotifyEnabled: false } } })
    puts "🔕 Automatische Tester-Benachrichtigung für Build #{BUILD} abgeschaltet."
  end
end

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

# Warten, bis der Build in TestFlight verfügbar ist, dann eine Mail nur an
# NOTIFY_EMAIL. Mail.app braucht beim ersten Mal die Freigabe unter
# Systemeinstellungen → Datenschutz & Sicherheit → Automation.
state = nil
45.times do
  state = api("GET", "/v1/builds/#{build['id']}")["data"].dig("attributes", "processingState")
  break unless state == "PROCESSING"
  sleep 60
end
if state == "VALID"
  version = api("GET", "/v1/builds/#{build['id']}?include=preReleaseVersion").fetch("included", []).first&.dig("attributes", "version")
  subject = "Klangradar #{version} (Build #{BUILD}) ist in TestFlight"
  body = "#{subject}.\n\n#{text}"
  script = <<~APPLESCRIPT
    on run argv
      tell application "Mail"
        set m to make new outgoing message with properties {subject:item 1 of argv, content:item 2 of argv, visible:false}
        tell m to make new to recipient at end of to recipients with properties {address:item 3 of argv}
        send m
      end tell
    end run
  APPLESCRIPT
  if system("osascript", "-e", script, subject, body, NOTIFY_EMAIL)
    puts "📧 Mail an #{NOTIFY_EMAIL} verschickt."
  else
    puts "⚠️ Mail an #{NOTIFY_EMAIL} konnte nicht verschickt werden (Mail.app/Automation-Freigabe prüfen)."
  end
else
  puts "⚠️ Build #{BUILD} ist nicht verarbeitet (#{state.inspect}) – keine Mail."
end
