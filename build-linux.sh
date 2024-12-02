#!/bin/bash -e

cd $(dirname ${BASH_SOURCE[0]})
ROOT_PATH="$(pwd)"
PATCH_PATH="$(pwd)/patches"
VCPKG_PATH="$(pwd)/vcpkg"
export PYMESH_PATH="$(pwd)/PyMesh"

# fetch pymesh if not found.
if [ ! -d "$PYMESH_PATH" ]; then
    git clone --depth 1 --recursive https://github.com/PyMesh/PyMesh.git
fi

# Apply patches
if [ ! -f "$PYMESH_PATH/build/.patch_done_tag" ]; then
    cd $PATCH_PATH
    declare -a PATCHES=($(find . -name '*.patch'))
    # git apply $PATCH_PATH/*.patch
    for patch in "${PATCHES[@]}"; do
        cd $ROOT_PATH/$(dirname $patch)
        git apply $PATCH_PATH/$patch
    done
    mkdir -p $PYMESH_PATH/build
    touch $PYMESH_PATH/build/.patch_done_tag
    cd $ROOT_PATH  # return to root path
fi

if [ ! -d "$VCPKG_PATH" ]; then
    git clone --depth 1 https://github.com/microsoft/vcpkg.git
    cd vcpkg
    ./bootstrap-vcpkg.sh
    cd $ROOT_PATH
fi

if [ ! -f "$VCPKG_PATH/installed/x64-linux/include/boost/align.hpp" ] ; then
    cd $VCPKG_PATH
    ./vcpkg install boost
    cd $ROOT_PATH
fi

export CMAKE_PREFIX_PATH="$VCPKG_PATH/installed/x64-linux"

if [ ! -f "$PYMESH_PATH/third_party/build/.all_done_tag" ] ; then
    cd $PYMESH_PATH/third_party
    if python3 build.py all ; then
        touch $PYMESH_PATH/third_party/build/.all_done_tag
    fi
    cd $ROOT_PATH
fi

if [ ! -f "$PYMESH_PATH/build/Makefile" ] ; then
    cd "$PYMESH_PATH/build"
    cmake ..
fi

if [ ! -f "$PYMESH_PATH/build/.all_done_tag" ] ; then
    cd "$PYMESH_PATH/build"
    cmake --build . && cmake --build . --target tests && touch $PYMESH_PATH/build/.all_done_tag
fi
