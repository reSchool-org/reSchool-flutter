# описание podspec есть в http://guides.cocoapods.org/syntax/podspec.html
# перед публикацией проверяем командой pod lib lint home_widget.podspec
Pod::Spec.new do |s|
  s.name             = 'home_widget'
  s.version          = '0.0.1'
  s.summary          = 'A new flutter plugin project.'
  s.description      = <<-DESC
A new flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'home_widget/Sources/home_widget/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'

  # во flutter.framework нет i386, поддерживаются только симуляторы x86_64
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64' }
  
  # отключаем явные модули в xcode 26, иначе расширения виджетов не находят модуль flutter
  s.user_target_xcconfig = { 'SWIFT_ENABLE_EXPLICIT_MODULES' => 'NO' }
  s.swift_version = '5.0'
end
