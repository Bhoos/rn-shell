cmake_minimum_required(VERSION 3.13)
project(rnshellupdates)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_VERBOSE_MAKEFILE ON)

find_package(ReactAndroid REQUIRED CONFIG)
find_package(fbjni REQUIRED CONFIG)

# The plugin loader (../cpp, shared with iOS) and its JNI glue
add_library(rnshellupdates SHARED ../cpp/RNShellPlugins.cpp src/main/cpp/OnLoad.cpp)
target_include_directories(rnshellupdates PRIVATE ../cpp)
target_link_libraries(rnshellupdates ReactAndroid::jsi ReactAndroid::reactnative fbjni::fbjni)
