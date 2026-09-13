# настройки уровня проекта
cmake_minimum_required(VERSION 3.14)
project(reSchool LANGUAGES CXX)

# путь к заголовкам atl и mfc для flutter_secure_storage_windows,
# ищем самую свежую версию msvc, где atl есть
file(GLOB MSVC_VERSIONS "C:/Program Files/Microsoft Visual Studio/2022/*/VC/Tools/MSVC/*")
list(SORT MSVC_VERSIONS ORDER DESCENDING)
foreach(MSVC_PATH ${MSVC_VERSIONS})
  if(EXISTS "${MSVC_PATH}/atlmfc/include")
    include_directories("${MSVC_PATH}/atlmfc/include")
    link_directories("${MSVC_PATH}/atlmfc/lib/x64")
    message(STATUS "Found ATL at: ${MSVC_PATH}/atlmfc")
    break()
  endif()
endforeach()

# имя исполняемого файла приложения,
# меняем тут, если хотим другое имя на диске
set(BINARY_NAME "reSchool")

# явно включаем современное поведение cmake,
# иначе свежие версии засыпят предупреждениями
cmake_policy(VERSION 3.14...3.25)

# параметр конфигурации сборки
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# настройки для режима сборки profile
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# везде работаем в юникоде
add_definitions(-DUNICODE -D_UNICODE)

# настройки компиляции, общие почти для всех целей
# добавлять сюда что то новое стоит осторожно: плагины по умолчанию
# зовут эту функцию, так что в большинстве случаев правильнее
# дописать параметр конкретной цели
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
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
endif()

# сборка приложения, подробности в runner/CMakeLists.txt
add_subdirectory("runner")


# сгенерированные правила сборки плагинов,
# они же прицепляют плагины к приложению
include(flutter/generated_plugins.cmake)

# These plugins still compile C++/WinRT with the legacy /await switch.
# Keep its compatibility opt-in scoped to them until their upstream migration.
foreach(plugin local_auth_windows_plugin permission_handler_windows_plugin)
  if(TARGET ${plugin})
    target_compile_definitions(${plugin} PRIVATE
      _SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)
  endif()
endforeach()


# установка
# вспомогательные файлы кладём рядом с бинарником, чтобы он запускался
# прямо оттуда, а отдельный бандл, как на linux, не собираем,
# иначе сборка и запуск из visual studio работать не будут
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# шаг install делаем шагом по умолчанию, без него не запустить
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# копируем нативные ресурсы, которые притащил build.dart из всех пакетов
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
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
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
