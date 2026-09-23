cmake_minimum_required(VERSION 3.22)
project(najwa_whisper CXX C)

set(CMAKE_CXX_STANDARD 17)

# whisper.cpp checkout (passed in from Gradle; see gradle.properties).
if (NOT WHISPER_CPP_DIR)
    message(FATAL_ERROR "WHISPER_CPP_DIR not set")
endif ()

# Build ggml + whisper as static libs from source, CPU only. Same knobs as the
# upstream Android example: armv8.2 fp16 arithmetic is what makes int8/fp16
# matmuls fast on a modern big.LITTLE SoC.
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
if (${ANDROID_ABI} STREQUAL "arm64-v8a")
    add_compile_options(-march=armv8.2-a+fp16)
endif ()
add_compile_options(-O3 -ffunction-sections -fdata-sections -fvisibility=hidden)

add_subdirectory(${WHISPER_CPP_DIR} ${CMAKE_BINARY_DIR}/whisper.cpp)

find_library(LOG_LIB log)

add_library(najwa_whisper SHARED najwa_jni.cpp)
target_include_directories(najwa_whisper PRIVATE ${WHISPER_CPP_DIR}/include ${WHISPER_CPP_DIR}/ggml/include)
target_link_libraries(najwa_whisper PRIVATE whisper ${LOG_LIB} android)
target_link_options(najwa_whisper PRIVATE -Wl,--gc-sections -Wl,--exclude-libs,ALL)
