require 'json'
gem 'xcodeproj', '1.27.0'
require 'xcodeproj'

# меняем только временную копию раннера, данные подписи в проект и артефакты не попадают
platform, config_path = ARGV
raise 'Invalid platform' unless %w[ios macos].include?(platform)
config = JSON.parse(File.read(config_path))
project = Xcodeproj::Project.open("#{platform}/Runner.xcodeproj")
config.fetch('profiles').each do |name, profile|
  target = project.targets.find { |candidate| candidate.name == name }
  raise "Missing target #{name}" unless target
  target.build_configurations.each do |configuration|
    next unless configuration.name == 'Release'
    settings = configuration.build_settings
    settings.keys.grep(/\ACODE_SIGN_IDENTITY/).each { |key| settings.delete(key) }
    settings['CODE_SIGN_STYLE'] = 'Manual'
    settings['CODE_SIGN_IDENTITY'] = config.fetch('identity')
    settings['DEVELOPMENT_TEAM'] = config.fetch('team')
    settings['PROVISIONING_PROFILE_SPECIFIER'] = profile.fetch('uuid')
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = profile.fetch('bundle')
  end
end
project.save
