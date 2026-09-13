cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# цель приложения, а чтобы поменять имя, правим BINARY_NAME
# в CMakeLists.txt уровнем выше, а не тут,
# иначе flutter run перестанет работать
# новые исходники приложения дописываем сюда же
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# накатываем стандартный набор настроек сборки,
# приложениям с другими требованиями это можно убрать
apply_standard_settings(${BINARY_NAME})

# версию сборки прокидываем в препроцессор
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# глушим макросы windows, которые конфликтуют с функциями стандартной библиотеки
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# библиотеки и каталоги заголовков, от которых зависим,
# дописываем сюда же
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# тут отрабатывает сам flutter, эту часть убирать нельзя
add_dependencies(${BINARY_NAME} flutter_assemble)
