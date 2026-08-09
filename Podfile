# 高德导航 SDK。不加 use_frameworks! → 静态链接，Swift 侧通过桥接头引用。
# AMapNavi 会自动带上基础包 AMapFoundation。
platform :ios, '15.0'

target 'NavApp' do
  pod 'AMapNavi'
end

# 关掉每个 pod 的 code sign（未签名 CI 打包更干净），并统一部署版本
post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      config.build_settings['EXPANDED_CODE_SIGN_IDENTITY'] = ''
    end
  end
end
