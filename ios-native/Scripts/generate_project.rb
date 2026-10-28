#!/usr/bin/env ruby

require "pathname"
require "fileutils"
require "xcodeproj"

root = Pathname.new(__dir__).parent.expand_path
project_path = root.join("KlangradarNative.xcodeproj")

FileUtils.rm_rf(project_path)
project = Xcodeproj::Project.new(project_path.to_s)
project.root_object.attributes["LastSwiftUpdateCheck"] = "2660"
project.root_object.attributes["LastUpgradeCheck"] = "2660"

app_target = project.new_target(
  :application,
  "KlangradarNative",
  :ios,
  "17.0",
  nil,
  :swift
)

test_target = project.new_target(
  :unit_test_bundle,
  "KlangradarNativeTests",
  :ios,
  "17.0",
  nil,
  :swift
)
test_target.add_dependency(app_target)

ui_test_target = project.new_target(
  :ui_test_bundle,
  "KlangradarNativeUITests",
  :ios,
  "17.0",
  nil,
  :swift
)
ui_test_target.add_dependency(app_target)

# Widget-Extension (Homescreen-/Sperrbildschirm-Widget + Live Activity).
widget_target = project.new_target(
  :app_extension,
  "KlangradarWidgets",
  :ios,
  "17.0",
  nil,
  :swift
)

# Notification Service Extension: lädt Bilder für Push-Mitteilungen.
notification_target = project.new_target(
  :app_extension,
  "KlangradarNotificationService",
  :ios,
  "17.0",
  nil,
  :swift
)

def add_files(project, target, root, folder, extensions, resources: false)
  base = root.join(folder)
  group = project.main_group.find_subpath(folder, true)
  group.set_source_tree("<group>")

  Dir.glob(base.join("**", "*").to_s).sort.each do |path|
    next unless File.file?(path)
    next unless extensions.include?(File.extname(path)) || extensions.include?(File.basename(path))

    relative_to_folder = Pathname.new(path).relative_path_from(base)
    parent = relative_to_folder.dirname.to_s == "." ? group : group.find_subpath(relative_to_folder.dirname.to_s, true)
    file = parent.new_file(path)

    if resources
      target.resources_build_phase.add_file_reference(file, true)
    else
      target.source_build_phase.add_file_reference(file, true)
    end
  end
end

def add_asset_catalogs(project, target, root, folder)
  base = root.join(folder)
  group = project.main_group.find_subpath(folder, true)
  group.set_source_tree("<group>")

  Dir.glob(base.join("**", "*.xcassets").to_s).sort.each do |path|
    relative_to_folder = Pathname.new(path).relative_path_from(base)
    parent = relative_to_folder.dirname.to_s == "." ? group : group.find_subpath(relative_to_folder.dirname.to_s, true)
    file = parent.new_file(path)
    target.resources_build_phase.add_file_reference(file, true)
  end
end

add_files(
  project,
  app_target,
  root,
  "KlangradarNative",
  [".swift"]
)
add_asset_catalogs(
  project,
  app_target,
  root,
  "KlangradarNative/Resources"
)

# Gemeinsamer Code für App und Widget (App-Group-Daten, Live-Activity-Typen).
add_files(project, app_target, root, "KlangradarShared", [".swift"])
widget_shared_group = project.main_group.find_subpath("KlangradarShared", true)
widget_shared_group.files.each { |file| widget_target.source_build_phase.add_file_reference(file, true) }
add_files(project, widget_target, root, "KlangradarWidgets", [".swift"])
widget_files_group = project.main_group.find_subpath("KlangradarWidgets", true)
widget_files_group.new_file(root.join("KlangradarWidgets", "Info.plist").to_s)

add_files(project, notification_target, root, "KlangradarNotificationService", [".swift"])
project.main_group.find_subpath("KlangradarNotificationService", true).new_file(root.join("KlangradarNotificationService", "Info.plist").to_s)

# Extension in die App einbetten.
app_target.add_dependency(widget_target)
app_target.add_dependency(notification_target)
embed_phase = app_target.new_copy_files_build_phase("Embed Foundation Extensions")
embed_phase.symbol_dst_subfolder_spec = :plug_ins
embed_build_file = embed_phase.add_file_reference(widget_target.product_reference, true)
embed_build_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
embed_notification_file = embed_phase.add_file_reference(notification_target.product_reference, true)
embed_notification_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }

# Datenschutz-Manifest (App-Store-Pflicht) als Ressource einbinden.
privacy_manifest = app_target.project.main_group.find_subpath("KlangradarNative/Resources", true).new_reference(root.join("KlangradarNative", "Resources", "PrivacyInfo.xcprivacy").to_s)
app_target.resources_build_phase.add_file_reference(privacy_manifest, true)
# "Neu in Klangradar" (auch Quelle für den TestFlight-Testhinweis).
whats_new = app_target.project.main_group.find_subpath("KlangradarNative/Resources", true).new_reference(root.join("KlangradarNative", "Resources", "WhatsNew.json").to_s)
app_target.resources_build_phase.add_file_reference(whats_new, true)

secrets_path = root.join("Config", "Secrets.plist")
if secrets_path.exist?
  config_group = project.main_group.find_subpath("Config", true)
  secrets_reference = config_group.new_file(secrets_path.to_s)
  app_target.resources_build_phase.add_file_reference(secrets_reference, true)
end

add_files(
  project,
  test_target,
  root,
  "KlangradarNativeTests",
  [".swift"]
)
add_files(project, ui_test_target, root, "KlangradarNativeUITests", [".swift"])

# Version/Build kommen aus dem lokalen Deploy-Zähler (~/.klangradar-build-number,
# siehe deploy-iphone.sh): 723 -> 7.2.3. Als Build-Phase, damit die Nummer auch
# bei Builds aus Xcode oder mit anderen Skripten stimmt (sonst gilt der
# Projekt-Standard 1.0). Deploy-Builds übergeben CURRENT_PROJECT_VERSION
# explizit (= Zähler + 1) und haben Vorrang vor dem Zählerstand.
version_phase = app_target.new_shell_script_build_phase("Version aus Build-Zähler")
version_phase.always_out_of_date = "1"
version_phase.shell_script = <<~'SH'
  BUILD="${CURRENT_PROJECT_VERSION}"
  COUNTER="$HOME/.klangradar-build-number"
  if [ "$BUILD" = "1" ] && [ -f "$COUNTER" ]; then BUILD=$(cat "$COUNTER"); fi
  case "$BUILD" in ''|*[!0-9]*) exit 0 ;; esac
  if [ "$BUILD" -le 1 ]; then exit 0; fi
  VERSION="$((BUILD / 100)).$(((BUILD / 10) % 10)).$((BUILD % 10))"
  PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
SH

widget_version_phase = widget_target.new_shell_script_build_phase("Version aus Build-Zähler")
widget_version_phase.always_out_of_date = "1"
# Widget und App müssen dieselbe Version tragen, sonst lehnt App Store Connect den Upload ab.
widget_version_phase.shell_script = version_phase.shell_script
notification_version_phase = notification_target.new_shell_script_build_phase("Version aus Build-Zähler")
notification_version_phase.always_out_of_date = "1"
notification_version_phase.shell_script = version_phase.shell_script

app_target.build_configurations.each do |config|
  config.build_settings.merge!(
    "ENABLE_USER_SCRIPT_SANDBOXING" => "NO",
    "ASSETCATALOG_COMPILER_APPICON_NAME" => "AppIcon",
    # Alternative App-Icons für Klangradar Plus (Claude Code, 27.10.2026)
    "ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES" => "AppIcon-Nacht AppIcon-Gold AppIcon-Indigo AppIcon-Mono",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME" => "AccentColor",
    "CODE_SIGN_STYLE" => "Automatic",
    "CURRENT_PROJECT_VERSION" => "1",
    "DEVELOPMENT_ASSET_PATHS" => "",
    "DEVELOPMENT_TEAM" => "DVH3MYQ64A",
    # Push (aps-environment) und Sign in with Apple.
    "CODE_SIGN_ENTITLEMENTS" => "KlangradarNative/KlangradarNative.entitlements",
    "ENABLE_PREVIEWS" => "YES",
    "GENERATE_INFOPLIST_FILE" => "YES",
    # Erstellt von Claude Code (26.10.2026): Die eigene Info.plist wurde
    # bisher nicht eingebunden – dadurch fehlte das URL-Schema
    # de.klangradar.native:// (Widget, Live Activity, Spotlight, Push-Links).
    # Die INFOPLIST_KEY_*-Einträge unten werden mit der Datei zusammengeführt.
    "INFOPLIST_FILE" => "KlangradarNative/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName" => "Klangradar",
    "INFOPLIST_KEY_LSApplicationCategoryType" => "public.app-category.music",
    # Nur Standard-HTTPS — erspart die Exportkontroll-Frage bei jedem Upload.
    "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption" => "NO",
    "INFOPLIST_KEY_NSSupportsLiveActivities" => "YES",
    "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription" => "Klangradar nutzt deinen Standort, um Konzerte in deiner Nähe zu zeigen.",
    "INFOPLIST_KEY_NSContactsUsageDescription" => "Klangradar gleicht deine Kontakte verschlüsselt ab, damit du Freunde findest, die Klangradar schon nutzen. Deine Kontakte werden nicht gespeichert.",
    # Nutzerwunsch: passive Erkennung "warst du bei diesem gemerkten Konzert?"
    # per Geofencing (siehe AttendanceLocationMonitor) — braucht laut Apple
    # sowohl die When-In-Use- als auch diese Always-Beschreibung. Kein
    # UIBackgroundModes-Eintrag nötig: startMonitoring(for:) weckt die App
    # eigenständig, auch ohne den Background-Mode "location" (der nur für
    # fortlaufende Updates via startUpdatingLocation gebraucht wird und ohne
    # entsprechenden Info.plist-Eintrag sofort abstürzt).
    "INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription" => "Klangradar erkennt automatisch, wenn du bei einem gemerkten Konzert bist, und fragt dich dann per Benachrichtigung, ob du es als besucht markieren möchtest.",
    "INFOPLIST_KEY_NSCameraUsageDescription" => "Klangradar nutzt die Kamera, um ein Profilbild aufzunehmen.",
    "INFOPLIST_KEY_NSPhotoLibraryUsageDescription" => "Klangradar nutzt deine Fotomediathek, um ein Profilbild auszuwählen.",
    "INFOPLIST_KEY_NSFaceIDUsageDescription" => "Klangradar nutzt Face ID, um deinen Account zu schützen.",
    # Fehlten hier bislang, obwohl vom Code benötigt (SpeechSearchController,
    # AddToCalendarView) — dieses Skript ist die EINZIGE Quelle der Wahrheit
    # für die generierte Info.plist (project.pbxproj wird bei jedem Lauf
    # komplett neu erzeugt, FileUtils.rm_rf oben); ein Key, der nur direkt in
    # project.pbxproj steht, verschwindet beim nächsten `generate_project.rb`
    # kommentarlos wieder — genau das ist der Sprachsuche-Berechtigung schon
    # einmal passiert (fehlende Beschreibung lässt iOS beim ersten Zugriff
    # auf ein privacy-sensitives API hart abstürzen, kein catchbarer Fehler).
    "INFOPLIST_KEY_NSMicrophoneUsageDescription" => "Klangradar nutzt das Mikrofon nur, wenn du die Sprachsuche startest.",
    "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription" => "Klangradar wandelt deine Sucheingabe in Text um.",
    "INFOPLIST_KEY_NSCalendarsWriteOnlyAccessUsageDescription" => "Klangradar legt Konzerte nur nach deiner Bestätigung in deinem Kalender an.",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents" => "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation" => "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad" => "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone" => "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "IPHONEOS_DEPLOYMENT_TARGET" => "17.0",
    "MARKETING_VERSION" => "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER" => "de.klangradar.native",
    "PRODUCT_NAME" => "$(TARGET_NAME)",
    "SUPPORTED_PLATFORMS" => "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST" => "NO",
    "SWIFT_EMIT_LOC_STRINGS" => "YES",
    "SWIFT_STRICT_CONCURRENCY" => "complete",
    "SWIFT_VERSION" => "6.0",
    "TARGETED_DEVICE_FAMILY" => "1,2"
  )
end

widget_target.build_configurations.each do |config|
  config.build_settings.merge!(
    "ENABLE_USER_SCRIPT_SANDBOXING" => "NO",
    "CODE_SIGN_STYLE" => "Automatic",
    "CODE_SIGN_ENTITLEMENTS" => "KlangradarWidgets/KlangradarWidgets.entitlements",
    "CURRENT_PROJECT_VERSION" => "1",
    "DEVELOPMENT_TEAM" => "DVH3MYQ64A",
    "GENERATE_INFOPLIST_FILE" => "YES",
    "INFOPLIST_FILE" => "KlangradarWidgets/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName" => "Klangradar",
    "INFOPLIST_KEY_NSHumanReadableCopyright" => "",
    "IPHONEOS_DEPLOYMENT_TARGET" => "17.0",
    "LD_RUNPATH_SEARCH_PATHS" => "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
    "MARKETING_VERSION" => "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER" => "de.klangradar.native.widgets",
    "PRODUCT_NAME" => "$(TARGET_NAME)",
    "SKIP_INSTALL" => "YES",
    "SUPPORTED_PLATFORMS" => "iphoneos iphonesimulator",
    "SWIFT_EMIT_LOC_STRINGS" => "YES",
    "SWIFT_STRICT_CONCURRENCY" => "complete",
    "SWIFT_VERSION" => "6.0",
    "TARGETED_DEVICE_FAMILY" => "1,2"
  )
end

notification_target.build_configurations.each do |config|
  config.build_settings.merge!(
    "ENABLE_USER_SCRIPT_SANDBOXING" => "NO",
    "CODE_SIGN_STYLE" => "Automatic",
    "CURRENT_PROJECT_VERSION" => "1",
    "DEVELOPMENT_TEAM" => "DVH3MYQ64A",
    "GENERATE_INFOPLIST_FILE" => "YES",
    "INFOPLIST_FILE" => "KlangradarNotificationService/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName" => "Klangradar",
    "IPHONEOS_DEPLOYMENT_TARGET" => "17.0",
    "LD_RUNPATH_SEARCH_PATHS" => "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
    "MARKETING_VERSION" => "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER" => "de.klangradar.native.notification-service",
    "PRODUCT_NAME" => "$(TARGET_NAME)",
    "SKIP_INSTALL" => "YES",
    "SUPPORTED_PLATFORMS" => "iphoneos iphonesimulator",
    "SWIFT_STRICT_CONCURRENCY" => "minimal",
    "SWIFT_VERSION" => "5.0",
    "TARGETED_DEVICE_FAMILY" => "1,2"
  )
end

test_target.build_configurations.each do |config|
  config.build_settings.merge!(
    "BUNDLE_LOADER" => "$(TEST_HOST)",
    "CODE_SIGN_STYLE" => "Automatic",
    "GENERATE_INFOPLIST_FILE" => "YES",
    "IPHONEOS_DEPLOYMENT_TARGET" => "17.0",
    "PRODUCT_BUNDLE_IDENTIFIER" => "de.klangradar.native.tests",
    "SWIFT_STRICT_CONCURRENCY" => "complete",
    "SWIFT_VERSION" => "6.0",
    "TEST_HOST" => "$(BUILT_PRODUCTS_DIR)/KlangradarNative.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/KlangradarNative"
  )
end

ui_test_target.build_configurations.each do |config|
  config.build_settings.merge!(
    "CODE_SIGN_STYLE" => "Automatic",
    "DEVELOPMENT_TEAM" => "DVH3MYQ64A",
    "GENERATE_INFOPLIST_FILE" => "YES",
    "IPHONEOS_DEPLOYMENT_TARGET" => "17.0",
    "PRODUCT_BUNDLE_IDENTIFIER" => "de.klangradar.native.uitests",
    "SWIFT_VERSION" => "6.0",
    "TEST_TARGET_NAME" => "KlangradarNative"
  )
end

project.build_configurations.each do |config|
  config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "17.0"
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app_target)
scheme.set_launch_target(app_target)
scheme.add_test_target(test_target)
scheme.add_test_target(ui_test_target)
scheme.save_as(project_path.to_s, "KlangradarNative", true)

puts "Generated #{project_path}"
