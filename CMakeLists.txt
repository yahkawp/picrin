cmake_minimum_required(VERSION 2.6)
cmake_policy(VERSION 2.6)
if(POLICY CMP0037)
  cmake_policy(SET CMP0037 OLD)
endif()

PROJECT(picrin)

# load extra cmake modules
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_SOURCE_DIR}/cmake/")

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY lib)
set(CMAKE_C_FLAGS "-O2 -Wall -Wextra")
set(CMAKE_C_FLAGS_DEBUG "-O0 -g -DDEBUG=1")

option(STRICT_C89_MODE "Strict c89 mode" OFF)
if(STRICT_C89_MODE)
  add_definitions(-std=c89 -ansi -pedantic)
endif()

include_directories(extlib/benz/include)

# build picrin
include(piclib/CMakeLists.txt)
include(contrib/CMakeLists.txt)
include(src/CMakeLists.txt)
include(docs/CMakeLists.txt)

# ----

# $ make run
add_custom_target(run bin/picrin DEPENDS repl)

# $ make test
add_custom_target(test DEPENDS test-r7rs test-contribs)

# $ make test-r7rs
add_custom_target(test-r7rs bin/picrin ${PROJECT_SOURCE_DIR}/t/r7rs-tests.scm DEPENDS repl)

# $ make test-contribs
add_custom_target(test-contribs DEPENDS ${CONTRIB_TESTS})

# $ make tak
add_custom_target(tak bin/picrin ${PROJECT_SOURCE_DIR}/etc/tak.scm DEPENDS repl)

# $ make lines
add_custom_target(lines find . -name "*.[chyl]" | xargs wc -l WORKING_DIRECTORY ${PROJECT_SOURCE_DIR})
