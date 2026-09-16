# Quassel for GNUstep

A native [GNUstep](https://gnustep.github.io/) desktop client for
[Quassel](https://quassel-irc.org/), built on the Objective-C protocol engine
from woboq's iQuassel iOS client.

The protocol layer is iQuassel's, essentially unmodified — it already spoke
Quassel's Qt `QDataStream`/`QVariant` wire format in pure Objective-C, and that
turned out to be byte-identical on GNUstep. The iOS interface is gone, replaced
by a native AppKit one: `NSOutlineView` for the buffer list, `NSTableView` for the
chat log and the channel member list, one desktop window instead of a
navigation stack.

> **Status: early but working.** It connects to a real Quassel core over TLS,
> authenticates, lists your networks and buffers, renders the chat log and shows
> channel members. See [Known issues](#known-issues).

---

## Requirements

A GNUstep system with AppKit — developed against a
[Gershwin](https://github.com/gershwin-desktop) layout (`/System/Library/...`).

| Component | Version tested |
|---|---|
| clang | 19.1.7 |
| libobjc2 (GNUstep runtime v2) | 2.2, ABI `gnustep-2.2` |
| gnustep-base | 1.31.1 |
| gnustep-gui | 0.32.0 |
| GnuTLS | 3.8.9 |
| zlib | 1.3.1 |

ARC, blocks, Objective-C literals and subscripting are all used, so the
GNUstep v2 runtime is required — the older GCC runtime will not work.

---

## Building

```sh
git clone https://github.com/pkgdemon/iquassel
cd iquassel
git checkout gnustep-native

./gnustep/build-app.sh     # -> gnustep/build/Quassel.app
```

There is also a headless build, useful for testing the protocol stack without
a GUI:

```sh
./gnustep/build-cli.sh     # -> gnustep/build/quasselcli
./gnustep/build/quasselcli <host> <port> <user> [password]
```

`quasselcli` connects, authenticates and prints the buffer list. It is the
fastest way to tell whether a problem is in the network layer or the interface.

## Installing

```sh
sudo cp -R gnustep/build/Quassel.app /Local/Applications/
sudo make_services          # register with Workspace
```

Then launch it:

```sh
openapp Quassel
# or directly:
/Local/Applications/Quassel.app/Quassel
```

Settings live in `~/Library/Preferences` and can be pre-seeded:

```sh
defaults write Quassel hostName core.example.org
defaults write Quassel port     4242
defaults write Quassel userName yourname
```

---

## Testing without a core

`gnustep/mockcore.py` is a minimal Quassel core speaking the legacy protocol —
enough of the handshake to drive the client from `ClientInit` through to a
populated buffer list. It serves two fake networks and needs no configuration.

```sh
python3 gnustep/mockcore.py 4242 &
./gnustep/build/quasselcli 127.0.0.1 4242 tester secret
```

`gnustep/probecore.py` asks a *real* core which handshakes it supports, which is
the first thing to run when a connection misbehaves:

```sh
python3 gnustep/probecore.py your-core-host 4242
```

---

## How it is put together

```
   NSOutlineView        NSTableView          NSTextField
   (buffer list)        (chat log)           (input)
         \                   |                   /
          +---- MainWindowController (NSWindowController) ----+
                              |
                  QuasselCoreConnectionDelegate     <- the seam
                              |
                    QuasselCoreConnection           <- upstream iQuassel
                     QVariant / Message / BufferInfo
                              |
                       QuasselSocket                <- POSIX fd + GSTLSSession
                              |
                  GNUstep Foundation / AppKit
```

| Path | What it holds |
|---|---|
| `quassel-for-ios/quassel-for-ios/` | Upstream iQuassel. The protocol engine is used as-is; only five files changed, all to decouple it from the UI |
| `gnustep/Core/` | `QuasselSocket` (the transport) and `quasselcli` |
| `gnustep/Shims/` | `GCDAsyncSocket.h` — a `@compatibility_alias` so the 1,643-line engine needs no socket edits |
| `gnustep/UI/` | The AppKit interface |

### Notes for anyone hacking on this

Four things about GNUstep cost real debugging time and are worth knowing:

**NSStream cannot do STARTTLS.** gnustep-base installs its TLS handler inside
`-open` (`GSSocketStream.m:2064`, `+[GSTLSHandler tryInput:output:]`, called
immediately before `connect()`), reading `NSStreamSocketSecurityLevelKey` at
that instant. Setting the property afterwards is silently ignored. Quassel
upgrades *partway through* the handshake — `ClientInit` goes out in the clear
and TLS starts only once `ClientInitAck` reports `SupportSsl` — so `NSStream`
cannot express this protocol at all. `QuasselSocket` therefore owns a
non-blocking POSIX fd and layers gnustep-base's own `GSTLSSession` on top via
push/pull callbacks. libs-corebase is no help: it contains no TLS code, and
`CFStreamCreatePairWithSocketToHost` is an empty function body.

**CFBoolean does not bridge.** `(id)kCFBooleanFalse` responds to `-boolValue`
on Apple platforms; on GNUstep it raises
`NSCFType does not recognize boolValue`. iQuassel passes exactly that as a TLS
option, so it must be read defensively.

**`NSSplitView` will not give a third pane any width.** With three subviews,
gnustep-gui hands the third one zero width regardless of its frame or what the
delegate's sizing methods answer. The member list is therefore laid out with
explicit frames inside a container beside the chat log, rather than as a third
split pane.

**`GSInetOutputStream` starves its sibling.** It signals
`NSStreamEventHasSpaceAvailable` continuously while the socket is writable,
monopolising the run loop so `HasBytesAvailable` never arrives. Only relevant if
you go back to `NSStream`, but it is a nasty one to diagnose.

---

## Known issues

- Still young; expect rough edges outside the paths described above.
- Core credentials are stored **in the clear** in `~/Library/Preferences`.
  GNUstep has no Security.framework, so there is no keychain to put them in.
  `libsecret` would be the sensible fix.
- No certificate prompt — the client accepts whatever the core presents. This
  is inherited upstream behaviour (iQuassel sets
  `kCFStreamSSLValidatesCertificateChain: NO`) and is what makes self-signed
  cores work.
- Context menus and backlog-on-scroll are not implemented yet.
- The client speaks Quassel's legacy `ProtocolVersion 10` handshake. Cores
  still accept it, but the modern probing protocol is not implemented.

---

## Credits

Built on [iQuassel](https://github.com/woboq/iquassel) by
[woboq](https://woboq.com/), the native Objective-C Quassel client for iOS.
All of the protocol work is theirs.

[Quassel IRC](https://quassel-irc.org/) is by the Quassel Project.

## License

Dual licensed — GPLv3 and Woboq GmbH's private license. See the `LICENSE` file.
