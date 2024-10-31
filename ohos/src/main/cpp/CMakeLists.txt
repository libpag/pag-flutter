# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(NativeProject)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

add_library(flutter_ohos_texture_patch SHARED napi_init.cpp)
target_link_libraries(flutter_ohos_texture_patch PUBLIC libace_napi.z.so libace_ndk.z.so libnative_window.so libhilog_ndk.z.so)