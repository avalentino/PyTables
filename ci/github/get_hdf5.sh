#!/bin/bash
# inspired by https://github.com/h5py/h5py/blob/master/ci/get_hdf5_if_needed.sh

set -xeo pipefail

PROJECT_DIR="$(pwd)"
EXTRA_MPI_FLAGS=()
EXTRA_SERIAL_FLAGS=()
if [ -z ${HDF5_MPI+x} ]; then
    echo "Building serial"
    EXTRA_SERIAL_FLAGS=(-D "HDF5_ENABLE_THREADSAFE=ON" -D "HDF5_ALLOW_UNSUPPORTED=ON")
else
    echo "Building with MPI"
    EXTRA_MPI_FLAGS=(-D "HDF5_ENABLE_PARALLEL=ON")
fi

mkdir -p $HDF5_DIR
export LD_LIBRARY_PATH="$HDF5_DIR/lib:${LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="$HDF5_DIR/lib/pkgconfig:${PKG_CONFIG_PATH}"

# Keep in sync with "Prerequisites" in User's Guide (whenever mentioned).
LZO_VERSION="2.10"
ZSTD_VERSION="1.5.2"
LZ4_VERSION="1.9.4"
BZIP_VERSION="1.0.8"
ZLIB_VERSION="1.3.1"


echo "building HDF5"
if [[ "$OSTYPE" == "darwin"* ]]; then
    # brew install automake cmake pkg-config

    NPROC=$(sysctl -n hw.ncpu)
    pushd /tmp

    brew install automake pkg-config
    # Some of the dependencies built below (e.g. LZO) declare CMake minimums
    # older than 3.5, which CMake >= 4 refuses to configure.  This is the
    # supported escape hatch (the previous approach of pinning an old CMake
    # via "brew extract" into a local tap is now rejected by Homebrew).
    export CMAKE_POLICY_VERSION_MINIMUM=3.5

    # lzo
    curl -sLO https://www.oberhumer.com/opensource/lzo/download/lzo-$LZO_VERSION.tar.gz
    tar xzf lzo-$LZO_VERSION.tar.gz
    pushd lzo-$LZO_VERSION
    mkdir build
    cd build
    cmake -DCMAKE_INSTALL_PREFIX="$HDF5_DIR" -DENABLE_SHARED:bool=on ../
    make
    make install
    popd

    # zstd
    curl -sLO https://github.com/facebook/zstd/releases/download/v$ZSTD_VERSION/zstd-$ZSTD_VERSION.tar.gz
    tar xzf zstd-$ZSTD_VERSION.tar.gz
    pushd zstd-$ZSTD_VERSION
    cd build/cmake
    cmake -DCMAKE_INSTALL_PREFIX="$HDF5_DIR" -DENABLE_SHARED:bool=on
    make
    make install
    popd

    CFLAGS_ORIG="$CFLAGS"
    export CC="/usr/bin/clang"
    export CXX="/usr/bin/clang"
    export cc=$CC

    # lz4
    curl -sLO https://github.com/lz4/lz4/archive/refs/tags/v$LZ4_VERSION.tar.gz
    tar xzf v$LZ4_VERSION.tar.gz
    pushd lz4-$LZ4_VERSION
    make install PREFIX="$HDF5_DIR"
    popd

    # bzip2
    curl -sLO https://gitlab.com/bzip2/bzip2/-/archive/bzip2-$BZIP_VERSION/bzip2-bzip2-$BZIP_VERSION.tar.gz
    tar xzf bzip2-bzip2-$BZIP_VERSION.tar.gz
    pushd bzip2-bzip2-$BZIP_VERSION
    cat << EOF >> Makefile

libbz2.dylib: \$(OBJS)
	\$(CC) \$(LDFLAGS) -shared -Wl,-install_name -Wl,libbz2.dylib -o libbz2.$BZIP_VERSION.dylib \$(OBJS)
	cp libbz2.$BZIP_VERSION.dylib \${PREFIX}/lib/
	ln -s libbz2.$BZIP_VERSION.dylib \${PREFIX}/lib/libbz2.1.0.dylib
	ln -s libbz2.$BZIP_VERSION.dylib \${PREFIX}/lib/libbz2.dylib

EOF
    sed -i "" "s/CFLAGS=-Wall/CFLAGS=-fPIC -Wall/g" Makefile
    sed -i "" "s/all: libbz2.a/all: libbz2.dylib libbz2.a/g" Makefile
    make install PREFIX="$HDF5_DIR"
    popd

    # zlib
    curl -sLO https://zlib.net/fossils/zlib-$ZLIB_VERSION.tar.gz
    tar xzf zlib-$ZLIB_VERSION.tar.gz
    pushd zlib-$ZLIB_VERSION
    ./configure --prefix="$HDF5_DIR"
    make
    make install
    popd

    popd
else
    yum -y update
    yum install -y zlib-devel bzip2-devel lzo-devel
    NPROC=$(nproc)
fi

pushd /tmp

# Releases after 2.1.0 are tagged with the plain version only (e.g. "2.2.0");
# older releases use the "hdf5_X.Y.Z" tag convention.
curl -fsSL -o "hdf5-$HDF5_VERSION.tar.gz" "https://github.com/HDFGroup/hdf5/archive/refs/tags/${HDF5_VERSION}.tar.gz" \
    || curl -fsSL -o "hdf5-$HDF5_VERSION.tar.gz" "https://github.com/HDFGroup/hdf5/archive/refs/tags/hdf5_${HDF5_VERSION}.tar.gz"
mkdir -p "hdf5-$HDF5_VERSION"
tar -xzf "hdf5-$HDF5_VERSION.tar.gz" --strip-components=1 -C "hdf5-$HDF5_VERSION"
pushd "hdf5-$HDF5_VERSION"
# HDF5 2.x dropped the Autotools build system, so build with CMake.
cmake -S . -B build \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_INSTALL_PREFIX="$HDF5_DIR" \
    -D BUILD_TESTING=OFF \
    -D BUILD_STATIC_LIBS=OFF \
    -D HDF5_BUILD_EXAMPLES=OFF \
    -D HDF5_BUILD_TOOLS=OFF \
    -D HDF5_BUILD_UTILS=OFF \
    -D CMAKE_INSTALL_LIBDIR=lib \
    -D HDF5_ENABLE_ZLIB_SUPPORT=ON \
    -D ZLIB_ROOT="$HDF5_DIR" \
    "${EXTRA_SERIAL_FLAGS[@]}" \
    "${EXTRA_MPI_FLAGS[@]}"
make -C build -j "$NPROC"
make -C build install

file "$HDF5_DIR"/lib/*

popd
popd
