include(FetchContent)

# Build a minimal protobuf (runtime + protoc) as part of the tree and consume
# its exported targets (protobuf::libprotobuf, protobuf::protoc). This replaces
# the legacy manual-build + find_package/module flow, which is incompatible
# with modern CMake (protobuf's compat module reads the forbidden LOCATION
# target property).
set(protobuf_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_CONFORMANCE OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_PROTOC_BINARIES ON CACHE BOOL "" FORCE)
set(protobuf_INSTALL OFF CACHE BOOL "" FORCE)
set(protobuf_WITH_ZLIB OFF CACHE BOOL "" FORCE)
set(protobuf_MSVC_STATIC_RUNTIME ON CACHE BOOL "" FORCE)

FetchContent_Declare(
  protocolbuffers_protobuf
  GIT_REPOSITORY https://github.com/protocolbuffers/protobuf
  GIT_TAG        v3.21.12
)
FetchContent_MakeAvailable(protocolbuffers_protobuf)

set(PROTO_ROOT ${CMAKE_SOURCE_DIR}/tenseal/proto)

# Regenerate the C++ sources from the .proto files using the just-built protoc.
add_custom_command(
  OUTPUT
    ${PROTO_ROOT}/tensealcontext.pb.cc ${PROTO_ROOT}/tensealcontext.pb.h
    ${PROTO_ROOT}/tensors.pb.cc ${PROTO_ROOT}/tensors.pb.h
  COMMAND protobuf::protoc
          --proto_path=${PROTO_ROOT} --cpp_out=${PROTO_ROOT}
          ${PROTO_ROOT}/tensealcontext.proto ${PROTO_ROOT}/tensors.proto
  DEPENDS
    protobuf::protoc
    ${PROTO_ROOT}/tensealcontext.proto ${PROTO_ROOT}/tensors.proto
  COMMENT "Generating protobuf C++ sources"
  VERBATIM
)

include_directories(${PROTO_ROOT})
set(PROTO_SOURCES ${PROTO_ROOT}/tensealcontext.pb.cc
                  ${PROTO_ROOT}/tensors.pb.cc)

add_library(tenseal_proto ${PROTO_SOURCES})
target_link_libraries(tenseal_proto PUBLIC protobuf::libprotobuf)
