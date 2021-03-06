cmake_minimum_required(VERSION 2.8)

project (luv C ASM)

set(LUV_VERSION_MAJOR 1)
set(LUV_VERSION_MINOR 6)
set(LUV_VERSION_PATCH 1)
set(LUV_VERSION ${LUV_VERSION_MAJOR}.${LUV_VERSION_MINOR}.${LUV_VERSION_PATCH})

option(BUILD_MODULE "Build as module" ON)
option(BUILD_SHARED_LIBS "Build shared library" OFF)
option(WITH_SHARED_LIBUV "Link to a shared libuv library instead of static linking" OFF)

if (NOT WITH_LUA_ENGINE)
  set(WITH_LUA_ENGINE "LuaJIT"
    CACHE STRING "Link to LuaJIT or PUC Lua" FORCE)
  set_property(CACHE WITH_LUA_ENGINE
    PROPERTY STRINGS  "Lua;LuaJIT")
endif (NOT WITH_LUA_ENGINE)

if (NOT LUA_BUILD_TYPE)
  set(LUA_BUILD_TYPE "Static"
    CACHE STRING "Build Lua/LuaJIT as static, dynamic libary, or use system one" FORCE)
  set_property(CACHE LUA_BUILD_TYPE
    PROPERTY STRINGS  "Static;Dynamic;System")
endif (NOT LUA_BUILD_TYPE)

if (WITH_LUA_ENGINE STREQUAL Lua)
  add_definitions(-DLUA_USE_DLOPEN)
  set(USE_LUAJIT OFF)
else ()
  set(USE_LUAJIT ON)
endif ()

set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_SOURCE_DIR}/cmake/Modules/")

if (WITH_SHARED_LIBUV)
  find_package(Libuv)
  if (LIBUV_FOUND)
    include_directories(${LIBUV_INCLUDE_DIR})
  endif (LIBUV_FOUND)
else (WITH_SHARED_LIBUV)
  include(deps/uv.cmake)
endif (WITH_SHARED_LIBUV)

if (LUA_BUILD_TYPE STREQUAL System)
  if (USE_LUAJIT)
    find_package(LuaJIT)
    if (LUAJIT_FOUND)
      include_directories(${LUAJIT_INCLUDE_DIR})
      link_directories(${LUAJIT_LIBRARIES})
    endif (LUAJIT_FOUND)
  else (USE_LUAJIT)
    find_package(Lua)
    if (LUA_FOUND)
      include_directories(${LUA_INCLUDE_DIR})
      link_directories(${LUA_LIBRARIES})
    endif (LUA_FOUND)
  endif (USE_LUAJIT)

else (LUA_BUILD_TYPE STREQUAL System)
  if (LUA_BUILD_TYPE STREQUAL Static)
    SET(WITH_SHARED_LUA OFF)
  else (LUA_BUILD_TYPE STREQUAL Static)
    SET(WITH_SHARED_LUA ON)
  endif (LUA_BUILD_TYPE STREQUAL Static)
  if (USE_LUAJIT)
    include(deps/luajit.cmake)
    include_directories(deps/luajit/src)
  else(USE_LUAJIT)
    include(deps/lua.cmake)
    include_directories(deps/lua/src)
  endif (USE_LUAJIT)
endif (LUA_BUILD_TYPE STREQUAL System)

if (BUILD_MODULE)
  add_library(luv MODULE src/luv.c)
  set_target_properties(luv PROPERTIES PREFIX "")
else (BUILD_MODULE)
  add_library(luv src/luv.c)
  if (BUILD_SHARED_LIBS)
    set_target_properties(luv
      PROPERTIES VERSION ${LUV_VERSION} SOVERSION ${LUV_VERSION_MAJOR})
  endif (BUILD_SHARED_LIBS)
endif (BUILD_MODULE)

if(APPLE)
  set(CMAKE_SHARED_MODULE_CREATE_C_FLAGS
    "${CMAKE_SHARED_MODULE_CREATE_C_FLAGS} -flat_namespace -undefined suppress"
  )
  # execute_process(COMMAND which luajit OUTPUT_VARIABLE LUAJIT)
  # set(CMAKE_SHARED_MODULE_CREATE_C_FLAGS
  #   "${CMAKE_SHARED_MODULE_CREATE_C_FLAGS} -bundle_loader ${LUAJIT}"
  # )
endif()

if(WIN32)
  add_definitions(-DLUA_BUILD_AS_DLL -DLUA_LIB)
  if (USE_LUAJIT)
    target_link_libraries(luv uv luajit-5.1)
  else (USE_LUAJIT)
    target_link_libraries(luv uv lualib)
  endif (USE_LUAJIT)
  # replace /MD to /MT to avoid link msvcr*.dll
  set(CompilerFlags
    CMAKE_C_FLAGS
    CMAKE_C_FLAGS_DEBUG
    CMAKE_C_FLAGS_MINSIZEREL
    CMAKE_C_FLAGS_RELWITHDEBINFO
    CMAKE_C_FLAGS_RELEASE)
  foreach(CompilerFlag ${CompilerFlags})
    string(REPLACE "/MD" "/MT" ${CompilerFlag} "${${CompilerFlag}}")
  endforeach()
elseif("${CMAKE_SYSTEM_NAME}" MATCHES "Linux")
  target_link_libraries(luv uv rt)
else()
  target_link_libraries(luv uv)
endif()

if (BUILD_MODULE)
  if (WIN32)
    set(INSTALL_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")
  else (WIN32)
    set(INSTALL_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib/lua/${LUA_VERSION_MAJOR}.${LUA_VERSION_MINOR}")
  endif (WIN32)
else (BUILD_MODULE)
  set(INSTALL_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib"
    CACHE PATH "Installation directory for libraries")
  set(INSTALL_INC_DIR "${CMAKE_INSTALL_PREFIX}/include/luv"
    CACHE PATH "Installation directory for headers")
endif (BUILD_MODULE)

if (CMAKE_INSTALL_PREFIX)
  install(TARGETS luv
    ARCHIVE DESTINATION "${INSTALL_LIB_DIR}"
    LIBRARY DESTINATION "${INSTALL_LIB_DIR}"
  )
  if (NOT BUILD_MODULE)
    install(
      FILES src/luv.h src/util.h src/lhandle.h src/lreq.h
      DESTINATION "${INSTALL_INC_DIR}"
    )
  endif (NOT BUILD_MODULE)
endif (CMAKE_INSTALL_PREFIX)
