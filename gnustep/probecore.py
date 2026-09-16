#!/usr/bin/env python3
"""
probecore.py -- ask a Quassel core which handshake it supports.

iQuassel speaks the pre-2014 LEGACY handshake: it opens with a QVariant map
{MsgType: "ClientInit", ProtocolVersion: 10, ...}. Quassel 0.13 removed support
for that, so modern cores expect the "probing" handshake instead:

    client -> uint32  magic    = 0x42b33f00 | flags
                               flags: 0x01 encryption, 0x02 compression
    client -> uint32  proto    (repeated; high bit 0x80000000 marks the last)
                               low byte: 0x01 legacy, 0x02 datastream
    core   -> uint32  chosen   (0x00000000 means "none of those")

This probes both ways and reports what the core actually does.

usage: probecore.py <host> [port]
"""
import socket
import struct
import sys

MAGIC          = 0x42B33F00
FEATURE_ENCRYPT = 0x01
FEATURE_COMPRESS = 0x02

PROTO_LEGACY     = 0x01
PROTO_DATASTREAM = 0x02
LAST             = 0x80000000


def probe_modern(host, port, timeout=8):
    s = socket.create_connection((host, port), timeout=timeout)
    try:
        # Advertise both TLS and compression support, then offer both protocols.
        s.sendall(struct.pack(">I", MAGIC | FEATURE_ENCRYPT | FEATURE_COMPRESS))
        s.sendall(struct.pack(">I", PROTO_DATASTREAM))
        s.sendall(struct.pack(">I", PROTO_LEGACY | LAST))

        data = s.recv(4)
        if len(data) < 4:
            return ("no-reply", data)
        (reply,) = struct.unpack(">I", data)
        return ("ok", reply)
    finally:
        s.close()


def probe_legacy(host, port, timeout=8):
    """Send exactly what iQuassel sends and see whether anything comes back."""
    def u32(n):  return struct.pack(">I", n)
    def i32(n):  return struct.pack(">i", n)
    def qstr(t):
        b = t.encode("utf-16-be")
        return u32(len(b)) + b
    def var(tid, payload):
        return i32(tid) + b"\x00" + payload

    m = {
        "MsgType":         var(10, qstr("ClientInit")),
        "ProtocolVersion": var(2, i32(10)),
        "ClientVersion":   var(10, qstr("probe")),
        "UseSsl":          var(1, b"\x01"),
        "UseCompression":  var(1, b"\x00"),
    }
    body = u32(len(m))
    for k, v in m.items():
        body += qstr(k) + v
    blob = var(8, body)

    s = socket.create_connection((host, port), timeout=timeout)
    try:
        s.sendall(u32(len(blob)) + blob)
        s.settimeout(timeout)
        try:
            data = s.recv(4096)
        except socket.timeout:
            return ("timeout", b"")
        return ("ok", data)
    finally:
        s.close()


def main():
    host = sys.argv[1]
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 4242

    print("probing quassel core at %s:%d\n" % (host, port))

    # --- modern ---
    print("== modern (probing) handshake ==")
    try:
        status, reply = probe_modern(host, port)
        if status == "no-reply":
            print("   core closed without replying (%d bytes)" % len(reply))
        else:
            flags = (reply & 0xFF000000) >> 24
            proto = reply & 0x000000FF
            names = {0: "NONE", 1: "legacy", 2: "datastream"}
            print("   reply 0x%08X" % reply)
            print("   chosen protocol : %s" % names.get(proto, "unknown(%d)" % proto))
            print("   flags           : 0x%02X%s%s" % (
                flags,
                "  TLS" if flags & FEATURE_ENCRYPT else "",
                "  compression" if flags & FEATURE_COMPRESS else ""))
            if proto == 0:
                print("   -> core rejected both offered protocols")
            else:
                print("   -> CORE SPEAKS THE MODERN HANDSHAKE")
    except Exception as e:
        print("   failed: %s" % e)

    # --- legacy ---
    print("\n== legacy handshake (what iQuassel sends today) ==")
    try:
        status, data = probe_legacy(host, port)
        if status == "timeout":
            print("   sent ClientInit, core never replied  -> LEGACY NOT SUPPORTED")
            print("   (this is exactly the 'Connected - negotiating...' hang)")
        elif not data:
            print("   core closed the connection  -> LEGACY NOT SUPPORTED")
        else:
            print("   got %d bytes back: %s" % (len(data), data[:64].hex()))
            print("   -> core still answers the legacy handshake")
    except Exception as e:
        print("   failed: %s" % e)


if __name__ == "__main__":
    main()
