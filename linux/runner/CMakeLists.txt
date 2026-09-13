cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# цель приложения, а чтобы поменять имя, правим BINARY_NAME
# в CMakeLists.txt уровнем выше, а не тут,
# иначе flutter run перестанет работать
# новые исходники приложения дописываем сюда же
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# накатываем стандартный набор настроек сборки,
# приложениям с другими требованиями это можно убрать
apply_standard_settings(${BINARY_NAME})

# идентификатор приложения прокидываем в препроцессор
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# библиотеки, от которых зависим, дописываем сюда
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
