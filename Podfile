platform :ios, '17.0'

target 'Ethica' do
  use_frameworks! :linkage => :static

  pod 'FirebaseAuth'
  pod 'GoogleSignIn', '~> 8.0'
  pod 'FirebaseFirestore'
  pod 'FirebaseCore'
  pod 'SQLite.swift', '~> 0.15.3'
  pod 'lottie-ios', '~> 4.4'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'

      # Fix gRPC-Core compilation segfault
      if target.name == 'gRPC-Core'
        config.build_settings['GCC_OPTIMIZATION_LEVEL'] = '0'
        config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
      end
    end
  end

  # Disable resource bundle copying completely
  installer.generated_aggregate_targets.each do |aggregate_target|
    aggregate_target.xcconfigs.each do |config_name, config_file|
      xcconfig_path = aggregate_target.xcconfig_path(config_name)
      config_file.save_as(xcconfig_path)
    end
  end
end
