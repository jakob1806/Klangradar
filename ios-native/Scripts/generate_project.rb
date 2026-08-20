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

app_target.build_configurations.each do |config|
  config.build_settings.merge!(
    "ASSETCATALOG_COMPILER_APPICON_NAME" => "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME" => "AccentColor",
    "CODE_SIGN_STYLE" => "Automatic",
    "CURRENT_PROJECT_VERSION" => "1",
    "DEVELOPMENT_ASSET_PATHS" => "",
    "ENABLE_PREVIEWS" => "YES",
    "GENERATE_INFOPLIST_FILE" => "YES",
    "INFOPLIST_KEY_CFBundleDisplayName" => "Klangradar",
    "INFOPLIST_KEY_LSApplicationCategoryType" => "public.app-category.music",
    "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription" => "Klangradar nutzt deinen Standort, um Konzerte in deiner Nähe zu zeigen.",
    "INFOPLIST_KEY_NSCameraUsageDescription" => "Klangradar nutzt die Kamera, um ein Profilbild aufzunehmen.",
    "INFOPLIST_KEY_NSPhotoLibraryUsageDescription" => "Klangradar nutzt deine Fotomediathek, um ein Profilbild auszuwählen.",
    "INFOPLIST_KEY_NSFaceIDUsageDescription" => "Klangradar nutzt Face ID, um deinen Account zu schützen.",
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

project.build_configurations.each do |config|
  config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "17.0"
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app_target)
scheme.set_launch_target(app_target)
scheme.add_test_target(test_target)
scheme.save_as(project_path.to_s, "KlangradarNative", true)

puts "Generated #{project_path}"
