Pod::Spec.new do |s|
  s.name             = 'AppThinnerReporter'
  s.version          = '0.1.0'
  s.summary          = 'iOS 现网运行时类与资源使用情况动态上报 Pod，输出规范统一数据供 AppThinner 看板导入'
  s.description      = <<-DESC
  在宿主 App 内采集运行时「已实现类」（RW_REALIZED）及资源使用情况（如 imageNamed），
  按与 AppThinner 约定好的 JSON 数据格式通过 uploadBlock 上报或落盘，供看板外部导入与静态结果融合。
  DESC
  s.homepage         = 'https://github.com/your-org/AppThinner_AI'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'AppThinner' => 'your-email@example.com' }
  s.source           = { :git => 'https://github.com/your-org/AppThinner_AI.git', :tag => s.version.to_s }
  s.ios.deployment_target = '12.0'
  s.source_files     = 'AppThinnerReporter/**/*.{h,m,mm}'
  s.public_header_files = 'AppThinnerReporter/**/*.h'
  s.frameworks       = 'Foundation', 'UIKit'
  s.libraries        = 'z'
end
