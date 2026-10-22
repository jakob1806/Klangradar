#!/usr/bin/env ruby
# frozen_string_literal: true

# Überträgt den App-Store-Auftritt aus ios-native/AppStore/ nach App Store
# Connect (nur in die bearbeitbare Version, nichts wird eingereicht):
#   - Kategorien (Musik, Unterhaltung), Name, Untertitel, Datenschutz-URL
#   - Beschreibung, Keywords, Werbetext, Support-/Marketing-URL, Neuerungen
#   - Screenshots aus AppStore/screenshots/{iphone-6.9,ipad-13}
# Zugangsdaten: ~/.appstoreconnect/config (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH).
# Aufruf: ruby Scripts/upload-app-store-listing.rb [--dry-run] [--skip-screenshots]
# Erstellt von Claude Code.

require "base64"
require "digest"
require "json"
require "net/http"
require "openssl"
require "uri"

Encoding.default_external = Encoding::UTF_8

BUNDLE_ID = "de.klangradar.native"
LOCALE = "de-DE"
ROOT = File.expand_path("..", __dir__)
LISTING = File.join(ROOT, "AppStore", LOCALE)
SCREENSHOT_SETS = { "iphone-6.9" => "APP_IPHONE_67", "ipad-13" => "APP_IPAD_PRO_3GEN_129" }.freeze
DRY_RUN = ARGV.include?("--dry-run")
SKIP_SCREENSHOTS = ARGV.include?("--skip-screenshots")

CONFIG = File.readlines(File.expand_path("~/.appstoreconnect/config")).to_h do |line|
  key, value = line.strip.split("=", 2)
  [key, value.to_s.delete_prefix('"').delete_suffix('"')]
end

def b64url(data) = Base64.urlsafe_encode64(data, padding: false)

def token
  @token = nil if @token_at && Time.now - @token_at > 900
  @token ||= begin
    @token_at = Time.now
    key = OpenSSL::PKey::EC.new(File.read(File.expand_path(CONFIG.fetch("ASC_KEY_PATH").sub("$HOME", Dir.home))))
    header = b64url({ alg: "ES256", kid: CONFIG.fetch("ASC_KEY_ID"), typ: "JWT" }.to_json)
    payload = b64url({ iss: CONFIG.fetch("ASC_ISSUER_ID"), iat: Time.now.to_i, exp: Time.now.to_i + 1200, aud: "appstoreconnect-v1" }.to_json)
    der = key.sign(OpenSSL::Digest.new("SHA256"), "#{header}.#{payload}")
    r, s = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00") }
    "#{header}.#{payload}.#{b64url(r + s)}"
  end
end

def api(method, path, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  request = Net::HTTP.const_get(method.capitalize).new(uri)
  request["Authorization"] = "Bearer #{token}"
  request["Content-Type"] = "application/json"
  request.body = body.to_json if body
  if DRY_RUN && method != :get
    puts "  [dry-run] #{method.upcase} #{path}"
    return { "data" => { "id" => "dry-run", "attributes" => {} } }
  end
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
  raise "#{method.upcase} #{path} → #{response.code}: #{response.body}" unless response.code.start_with?("2")
  response.body.to_s.empty? ? {} : JSON.parse(response.body)
end

def text(name)
  path = File.join(LISTING, "#{name}.txt")
  File.exist?(path) ? File.read(path, encoding: "UTF-8").strip : nil
end

app = api(:get, "/v1/apps?filter[bundleId]=#{BUNDLE_ID}")["data"].first or abort("App #{BUNDLE_ID} nicht gefunden")
app_id = app["id"]
puts "App: #{app['attributes']['name']} (#{app_id})"

# --- App-Info: Kategorien, Name, Untertitel ---------------------------------
infos = api(:get, "/v1/apps/#{app_id}/appInfos")["data"]
editable_info = infos.find { |info| %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED].include?(info.dig("attributes", "state") || info.dig("attributes", "appStoreState")) } || infos.first
api(:patch, "/v1/appInfos/#{editable_info['id']}", {
  data: { type: "appInfos", id: editable_info["id"], relationships: {
    primaryCategory: { data: { type: "appCategories", id: "MUSIC" } },
    secondaryCategory: { data: { type: "appCategories", id: "ENTERTAINMENT" } }
  } }
})
puts "✓ Kategorien: Musik, Unterhaltung"

info_attrs = { name: text("name"), subtitle: text("subtitle"), privacyPolicyUrl: "https://klangradar.com/datenschutz" }.compact
info_loc = api(:get, "/v1/appInfos/#{editable_info['id']}/appInfoLocalizations")["data"].find { |l| l.dig("attributes", "locale") == LOCALE }
if info_loc
  api(:patch, "/v1/appInfoLocalizations/#{info_loc['id']}", { data: { type: "appInfoLocalizations", id: info_loc["id"], attributes: info_attrs } })
else
  api(:post, "/v1/appInfoLocalizations", { data: { type: "appInfoLocalizations", attributes: info_attrs.merge(locale: LOCALE),
                                                   relationships: { appInfo: { data: { type: "appInfos", id: editable_info["id"] } } } } })
end
puts "✓ Name, Untertitel, Datenschutz-URL"

# --- Version: Beschreibung, Keywords, Screenshots ---------------------------
versions = api(:get, "/v1/apps/#{app_id}/appStoreVersions?filter[platform]=IOS&limit=10")["data"]
version = versions.find { |v| %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED].include?(v.dig("attributes", "appStoreState")) }
abort("Keine bearbeitbare App-Store-Version. Bitte in App Store Connect eine neue Version anlegen.") unless version
first_release = versions.none? { |v| v.dig("attributes", "appStoreState") == "READY_FOR_SALE" }
puts "Version: #{version.dig('attributes', 'versionString')} (#{version.dig('attributes', 'appStoreState')})"

version_attrs = {
  description: text("description"), keywords: text("keywords"), promotionalText: text("promotional_text"),
  supportUrl: "https://klangradar.com/impressum", marketingUrl: "https://klangradar.com"
}
version_attrs[:whatsNew] = text("release_notes") unless first_release # beim Erstrelease nicht erlaubt
version_attrs.compact!
version_loc = api(:get, "/v1/appStoreVersions/#{version['id']}/appStoreVersionLocalizations")["data"].find { |l| l.dig("attributes", "locale") == LOCALE }
version_loc_id =
  if version_loc
    api(:patch, "/v1/appStoreVersionLocalizations/#{version_loc['id']}", { data: { type: "appStoreVersionLocalizations", id: version_loc["id"], attributes: version_attrs } })
    version_loc["id"]
  else
    api(:post, "/v1/appStoreVersionLocalizations", { data: { type: "appStoreVersionLocalizations", attributes: version_attrs.merge(locale: LOCALE),
                                                             relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: version["id"] } } } } })["data"]["id"]
  end
puts "✓ Beschreibung, Keywords, Werbetext, URLs#{first_release ? '' : ', Neuerungen'}"

exit if SKIP_SCREENSHOTS

existing_sets = DRY_RUN && version_loc.nil? ? [] : api(:get, "/v1/appStoreVersionLocalizations/#{version_loc_id}/appScreenshotSets")["data"]
SCREENSHOT_SETS.each do |folder, display_type|
  files = Dir[File.join(ROOT, "AppStore", "screenshots", folder, "*.png")].sort
  next puts("– #{folder}: keine Screenshots gefunden") if files.empty?

  set = existing_sets.find { |s| s.dig("attributes", "screenshotDisplayType") == display_type }
  if set
    # Vorhandene Screenshots ersetzen, damit die Reihenfolge stimmt.
    api(:get, "/v1/appScreenshotSets/#{set['id']}/appScreenshots")["data"].each { |shot| api(:delete, "/v1/appScreenshots/#{shot['id']}") }
  else
    set = api(:post, "/v1/appScreenshotSets", { data: { type: "appScreenshotSets", attributes: { screenshotDisplayType: display_type },
                                                        relationships: { appStoreVersionLocalization: { data: { type: "appStoreVersionLocalizations", id: version_loc_id } } } } })["data"]
  end

  files.each do |file|
    data = File.binread(file)
    shot = api(:post, "/v1/appScreenshots", { data: { type: "appScreenshots", attributes: { fileName: File.basename(file), fileSize: data.bytesize },
                                                      relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: set["id"] } } } } })["data"]
    unless DRY_RUN
      shot.dig("attributes", "uploadOperations").each do |op|
        uri = URI(op["url"])
        request = Net::HTTP.const_get(op["method"].capitalize).new(uri)
        op["requestHeaders"].each { |h| request[h["name"]] = h["value"] }
        request.body = data.byteslice(op["offset"], op["length"])
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
        raise "Upload #{File.basename(file)} → #{response.code}" unless response.code.start_with?("2")
      end
    end
    api(:patch, "/v1/appScreenshots/#{shot['id']}", { data: { type: "appScreenshots", id: shot["id"], attributes: { uploaded: true, sourceFileChecksum: Digest::MD5.hexdigest(data) } } })
  end
  puts "✓ #{files.size} Screenshots (#{display_type})"
end
puts "Fertig. In App Store Connect prüfen; eingereicht wird nichts."
