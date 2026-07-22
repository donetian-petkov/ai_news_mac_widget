#!/usr/bin/env ruby
require 'fileutils'
require 'pathname'
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
NATIVE = File.join(ROOT, 'native')
PROJECT_PATH = File.join(NATIVE, 'AINewsMacWidget.xcodeproj')

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes['LastSwiftUpdateCheck'] = '1640'
project.root_object.attributes['LastUpgradeCheck'] = '1640'

def set_build_settings(target, settings)
  target.build_configurations.each do |config|
    settings.each do |key, value|
      config.build_settings[key] = value
    end
  end
end

def add_files(group, target, native_root, relative_paths)
  relative_paths.each do |relative_path|
    file_ref = group.new_file(File.basename(relative_path))
    target.source_build_phase.add_file_reference(file_ref)
  end
end

sources_group = project.main_group.new_group('Sources', 'Sources')
support_group = project.main_group.new_group('Support', 'Support')
resources_group = project.main_group.new_group('Resources', '.')

shared_group = sources_group.new_group('AINewsWidgetShared', 'AINewsWidgetShared')
app_group = sources_group.new_group('AINewsMacApp', 'AINewsMacApp')
widget_group = sources_group.new_group('AINewsWidgets', 'AINewsWidgetExtension')
widget_support_group = sources_group.new_group('AINewsWidgetExtensionSupport', 'AINewsWidgetExtensionSupport')

shared_target = project.new_target(:static_library, 'AINewsWidgetShared', :osx, '14.0')
app_target = project.new_target(:application, 'AINewsMacApp', :osx, '14.0')
widget_target = project.new_target(:app_extension, 'AINewsWidgets', :osx, '14.0')

common_settings = {
  'SWIFT_VERSION' => '5.0',
  'MACOSX_DEPLOYMENT_TARGET' => '14.0',
  'CLANG_ENABLE_MODULES' => 'YES',
  'CODE_SIGNING_ALLOWED' => 'NO'
}

set_build_settings(shared_target, common_settings.merge(
  'PRODUCT_NAME' => 'AINewsWidgetShared',
  'PRODUCT_MODULE_NAME' => 'AINewsWidgetShared',
  'DEFINES_MODULE' => 'YES',
  'SKIP_INSTALL' => 'YES'
))

set_build_settings(app_target, common_settings.merge(
  'PRODUCT_NAME' => 'AINewsMacApp',
  'PRODUCT_BUNDLE_IDENTIFIER' => 'com.donetianpetkov.ainewsmacwidget',
  'INFOPLIST_FILE' => 'Support/AINewsMacApp-Info.plist',
  'LD_RUNPATH_SEARCH_PATHS' => '$(inherited) @executable_path/../Frameworks @executable_path/../PlugIns',
  'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
  'SKIP_INSTALL' => 'NO'
))

set_build_settings(widget_target, common_settings.merge(
  'PRODUCT_NAME' => 'AINewsWidgets',
  'PRODUCT_BUNDLE_IDENTIFIER' => 'com.donetianpetkov.ainewsmacwidget.widgets',
  'INFOPLIST_FILE' => 'Support/AINewsWidgets-Info.plist',
  'APPLICATION_EXTENSION_API_ONLY' => 'YES',
  'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
  'SKIP_INSTALL' => 'YES'
))

shared_sources = Dir.glob(File.join(NATIVE, 'Sources/AINewsWidgetShared/*.swift'))
  .map { |path| Pathname(path).relative_path_from(Pathname(NATIVE)).to_s }
  .sort
app_sources = Dir.glob(File.join(NATIVE, 'Sources/AINewsMacApp/*.swift'))
  .map { |path| Pathname(path).relative_path_from(Pathname(NATIVE)).to_s }
  .sort
widget_sources = Dir.glob(File.join(NATIVE, 'Sources/AINewsWidgetExtension/*.swift'))
  .map { |path| Pathname(path).relative_path_from(Pathname(NATIVE)).to_s }
  .sort
widget_support_sources = Dir.glob(File.join(NATIVE, 'Sources/AINewsWidgetExtensionSupport/*.swift'))
  .map { |path| Pathname(path).relative_path_from(Pathname(NATIVE)).to_s }
  .sort

support_files = %w[
  Support/AINewsMacApp-Info.plist
  Support/AINewsWidgets-Info.plist
  Support/AINewsMacApp.entitlements
  Support/AINewsWidgets.entitlements
  Support/backend-launch.json
]

add_files(shared_group, shared_target, NATIVE, shared_sources)
add_files(app_group, app_target, NATIVE, app_sources)
add_files(widget_group, widget_target, NATIVE, widget_sources)
add_files(widget_support_group, widget_target, NATIVE, widget_support_sources)

support_files.each do |relative_path|
  support_group.new_file(File.basename(relative_path))
end
app_target.resources_build_phase.add_file_reference(support_group.files.find { |f| f.path == 'backend-launch.json' })

asset_catalog_ref = resources_group.new_file('Assets.xcassets')
app_target.resources_build_phase.add_file_reference(asset_catalog_ref)
widget_target.resources_build_phase.add_file_reference(asset_catalog_ref)

app_target.add_dependency(shared_target)
app_target.add_dependency(widget_target)
widget_target.add_dependency(shared_target)

app_target.frameworks_build_phase.add_file_reference(shared_target.product_reference)
widget_target.frameworks_build_phase.add_file_reference(shared_target.product_reference)

embed_extensions = app_target.new_copy_files_build_phase('Embed App Extensions')
embed_extensions.dst_subfolder_spec = '13'
embed_extensions.add_file_reference(widget_target.product_reference)

project.products_group ||= project.main_group['Products']
project.targets.each do |target|
  project.frameworks_group
  target.product_reference.include_in_index = '1' if target.product_reference
end

project.predictabilize_uuids
project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app_target)
scheme.set_launch_target(app_target)
scheme.save_as(PROJECT_PATH, 'AINewsMacApp', true)
