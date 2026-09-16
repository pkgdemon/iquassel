#!/bin/sh
#
# Builds Quassel.app -- the native GNUstep/AppKit client.
#
# Layout follows GNUstep convention (executable at bundle root, Resources/ with
# Info-gnustep.plist), not the flat iOS layout.
#
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/quassel-for-ios/quassel-for-ios"
GNU="$ROOT/gnustep"
OUT="$GNU/build"
APP="$OUT/Quassel.app"

mkdir -p "$OUT"

CFLAGS="-I$GNU/Shims -I$GNU/Core -I$GNU/UI -I$SRC \
  -I/System/Library/Headers \
  -fobjc-runtime=gnustep-2.0 -fblocks -fobjc-arc \
  -fconstant-string-class=NSConstantString \
  -DGNUSTEP -g -O0 -Wno-format -Wno-deprecated-declarations"

LDFLAGS="-L/System/Library/Libraries \
  -lgnustep-gui -lgnustep-base -lobjc -lBlocksRuntime -ldispatch \
  -lz -lgnutls -lgnustep-corebase -lm"

ENGINE="QuasselCoreConnection QVariant QBoolean SignedId Message BufferInfo \
        IrcUser IrcChannel QuasselUtils AppState"
CORE="QuasselSocket"
UI="QuasselAppDelegate MainWindowController BufferListController ChatViewController main"

OBJS=""
fail=0

compile() {   # $1 = source path, $2 = object stem
  printf "   %-28s" "$(basename "$1")"
  if clang -c "$1" -o "$OUT/$2.o" $CFLAGS 2>"$OUT/$2.err"; then
    echo "ok"
    OBJS="$OBJS $OUT/$2.o"
  else
    echo "FAIL"
    grep -m6 "error:" "$OUT/$2.err" | sed 's/^/        /'
    fail=1
  fi
}

echo "== engine =="
for f in $ENGINE; do compile "$SRC/$f.m" "$f"; done

echo "== core =="
for f in $CORE; do compile "$GNU/Core/$f.m" "$f"; done

echo "== ui =="
for f in $UI; do compile "$GNU/UI/$f.m" "ui_$f"; done

[ "$fail" -eq 0 ] || { echo "== build failed =="; exit 1; }

echo "== linking =="
mkdir -p "$APP/Resources"
clang -o "$APP/Quassel" $OBJS $LDFLAGS

# App icon. GNUstep reads NSIcon (and ApplicationIcon) from Info-gnustep.plist
# and resolves it against Resources/, the same way TextEdit.app and Player.app do.
cp "$GNU/UI/Quassel.png" "$APP/Resources/Quassel.png"

cat > "$APP/Resources/Info-gnustep.plist" <<'PLIST'
{
    ApplicationName = "Quassel";
    ApplicationDescription = "Quassel IRC client for GNUstep";
    ApplicationIcon = "Quassel.png";
    NSIcon = "Quassel.png";
    NSExecutable = "Quassel";
    NSPrincipalClass = "NSApplication";
    NSMainNibFile = "";
    GSMainMarkupFile = "";
    NSMainStoryboardFile = "";
    ApplicationRelease = "0.1";
    NSRole = "Application";
}
PLIST

echo "   $APP"
