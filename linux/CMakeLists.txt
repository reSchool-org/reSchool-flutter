# настройки уровня проекта
cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# имя исполняемого файла приложения,
# меняем тут, если хотим другое имя на диске
set(BINARY_NAME "reschool")
# уникальный идентификатор gtk приложения,
# как его выбирать, написано в вики gnome, раздел ChooseApplicationID
set(APPLICATION_ID "com.magisky.reschool")

# явно включаем современное поведение cmake,
# иначе свежие версии засыпят предупреждениями
cmake_policy(SET CMP0063 NEW)

# библиотеки из комплекта грузим из папки lib рядом с бинарником
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# корень файловой системы для кросс сборки
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# параметры конфигурации сборки
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# настройки компиляции, общие почти для всех целей
# добавлять сюда что то новое стоит осторожно: плагины по умолчанию
# зовут эту функцию, так что в большинстве случаев правильнее
# дописать параметр конкретной цели
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# правила сборки библиотеки flutter и его утилит
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# версию вытаскиваем из pubspec.yaml
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/../pubspec.yaml" pubspec_version REGEX "^version: [0-9]+\\.[0-9]+\\.[0-9]+")
if(pubspec_version MATCHES "version: ([0-9]+)\\.([0-9]+)\\.([0-9]+)(\\+([0-9]+))?")
  set(FLUTTER_VERSION_MAJOR "${CMAKE_MATCH_1}")
  set(FLUTTER_VERSION_MINOR "${CMAKE_MATCH_2}")
  set(FLUTTER_VERSION_PATCH "${CMAKE_MATCH_3}")
  set(FLUTTER_VERSION_BUILD "${CMAKE_MATCH_5}")
  if(FLUTTER_VERSION_BUILD STREQUAL "")
    set(FLUTTER_VERSION_BUILD 0)
  endif()
  set(FLUTTER_VERSION "${FLUTTER_VERSION_MAJOR}.${FLUTTER_VERSION_MINOR}.${FLUTTER_VERSION_PATCH}")
  message(STATUS "Loaded version from pubspec.yaml: ${FLUTTER_VERSION}+${FLUTTER_VERSION_BUILD}")
  
  add_compile_definitions(FLUTTER_VERSION="${FLUTTER_VERSION}")
  add_compile_definitions(FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR})
  add_compile_definitions(FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR})
  add_compile_definitions(FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH})
  add_compile_definitions(FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD})
endif()

# системные зависимости
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# сборка приложения, подробности в runner/CMakeLists.txt
add_subdirectory("runner")

# тут отрабатывает сам flutter, эту часть убирать нельзя
add_dependencies(${BINARY_NAME} flutter_assemble)

# запускаться будет только та копия бинарника, что лежит в собранном бандле:
# ресурсы должны быть на своих относительных местах, поэтому голый
# бинарник прячем в подпапку, а не оставляем в корне,
# как было бы по умолчанию
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# сгенерированные правила сборки плагинов,
# они же прицепляют плагины к приложению
include(flutter/generated_plugins.cmake)

# flutter_secure_storage тащит с собой старый json.hpp, а свежий clang
# считает его синтаксис литералов устаревшим и с -Werror роняет сборку,
# так что для этого плагина предупреждение глушим
if(TARGET flutter_secure_storage_linux_plugin)
  include(CheckCXXCompilerFlag)
  check_cxx_compiler_flag(-Wno-deprecated-literal-operator HAVE_WNO_DEPRECATED_LITERAL_OPERATOR)
  if(HAVE_WNO_DEPRECATED_LITERAL_OPERATOR)
    target_compile_options(flutter_secure_storage_linux_plugin PRIVATE -Wno-deprecated-literal-operator)
  endif()
endif()


# установка
# по умолчанию установка это просто переносимый бандл
# в каталоге сборки
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# каталог бандла каждый раз начинаем с чистого листа
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# копируем нативные ресурсы, которые притащил build.dart из всех пакетов
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# каталог с ресурсами перекопируем целиком каждую сборку,
# иначе от прошлой установки останется мусор
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# библиотеку aot ставим только в нерелизных сборках
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
