#!/bin/sh
#
# Phase 1 build: the headless Quassel core client.
#
# Compiles the kept protocol engine (unmodified iQuassel sources) plus the
# GNUstep socket replacement, and links a CLI harness. No UI, no UIKit.
#
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/quassel-for-ios/quassel-for-ios"
GNU="$ROOT/gnustep"
OUT="$GNU/build"

mkdir -p "$OUT"

CFLAGS="-I$GNU/Shims -I$GNU/Core -I$SRC \
  -I/System/Library/Headers \
  -fobjc-runtime=gnustep-2.0 -fblocks -fobjc-arc \
  -fconstant-string-class=NSConstantString \
  -DGNUSTEP -g -O0 -Wno-format"

LDFLAGS="-L/System/Library/Libraries \
  -lgnustep-base -lobjc -lBlocksRuntime -ldispatch -lz -lgnutls -lgnustep-corebase"

# Kept, unmodified iQuassel protocol/model sources.
ENGINE="QuasselCoreConnection QVariant QBoolean SignedId Message BufferInfo \
        IrcUser IrcChannel QuasselUtils AppState"

OBJS=""
fail=0

echo "== compiling engine =="
for f in $ENGINE; do
  printf "   %-24s" "$f.m"
  if clang -c "$SRC/$f.m" -o "$OUT/$f.o" $CFLAGS 2>"$OUT/$f.err"; then
    echo "ok"
    OBJS="$OBJS $OUT/$f.o"
  else
    echo "FAIL"
    sed 's/^/      /' "$OUT/$f.err" | grep -m5 "error:" || true
    fail=1
  fi
done

echo "== compiling gnustep layer =="
for f in QuasselSocket quasselcli; do
  printf "   %-24s" "$f.m"
  if clang -c "$GNU/Core/$f.m" -o "$OUT/$f.o" $CFLAGS 2>"$OUT/$f.err"; then
    echo "ok"
    OBJS="$OBJS $OUT/$f.o"
  else
    echo "FAIL"
    sed 's/^/      /' "$OUT/$f.err" | grep -m5 "error:" || true
    fail=1
  fi
done

[ "$fail" -eq 0 ] || { echo "== build failed =="; exit 1; }

echo "== linking =="
clang -o "$OUT/quasselcli" $OBJS $LDFLAGS
echo "   $OUT/quasselcli"
