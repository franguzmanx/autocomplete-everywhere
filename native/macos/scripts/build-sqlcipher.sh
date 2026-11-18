#!/bin/bash
set -euo pipefail
# Pinned upstream SQLCipher; CommonCrypto avoids third-party dynamic dependencies.
base="$(cd "$(dirname "$0")/.." && pwd)/.build/sqlcipher"
revision=58beb4a302f0e3c37341d2312cef521f858b1273
prefix="$base/install"
mkdir -p "$base"
if [[ ! -f "$prefix/lib/libsqlcipher.a" ]]; then
  {
  if [[ ! -d "$base/source/.git" ]]; then
    git init -q "$base/source"
    git -C "$base/source" remote add origin https://github.com/sqlcipher/sqlcipher.git
  fi
  git -C "$base/source" fetch --depth 1 origin "$revision"
  git -C "$base/source" checkout --detach "$revision"
  cd "$base/source"
  ./configure --with-tempstore=yes --enable-fts5 --disable-shared --enable-static \
    CFLAGS="-O2 -mmacosx-version-min=14.0 -DSQLITE_HAS_CODEC -DSQLITE_EXTRA_INIT=sqlcipher_extra_init -DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown -DSQLCIPHER_CRYPTO_CC" \
    LDFLAGS="-framework Security -framework CoreFoundation" --prefix="$prefix"
  make -j "$(sysctl -n hw.ncpu)" sqlite3.c
  mkdir -p "$prefix/include" "$prefix/lib/pkgconfig"
  xcrun clang -O2 -mmacosx-version-min=14.0 -DSQLITE_HAS_CODEC -DSQLITE_TEMP_STORE=3 \
    -DSQLITE_THREADSAFE=1 -DSQLITE_ENABLE_FTS5 -DSQLITE_EXTRA_INIT=sqlcipher_extra_init \
    -DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown -DSQLCIPHER_CRYPTO_CC -c sqlite3.c -o "$base/sqlcipher.o"
  xcrun ar rcs "$prefix/lib/libsqlcipher.a" "$base/sqlcipher.o"
  cp sqlite3.h "$prefix/include/sqlite3.h"
  cp LICENSE.md "$prefix/LICENSE"
  } >&2
fi
cat > "$prefix/lib/pkgconfig/sqlcipher.pc" <<PC
prefix=$prefix
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: SQLCipher
Description: Encrypted SQLite using macOS CommonCrypto
Version: 4.19.0
Libs: -L\${libdir} -lsqlcipher -framework Security -framework CoreFoundation
Cflags: -I\${includedir}
PC
printf '%s\n' "$prefix/lib/pkgconfig"
