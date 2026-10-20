#!/usr/bin/env python3
"""Builds a tiny fake IPA (with a fake arm64 Mach-O) used to test the C readers."""
import struct, sys, zipfile, plistlib

def macho(encrypted):
    cstring = b"preferredFramesPerSecond\0CADisplayLink\0hello\0"
    strtab = b"\0_OBJC_CLASS_$_CADisplayLink\0_OBJC_CLASS_$_MyGame\0_MTLCreateSystemDefaultDevice\0"
    s1 = 1; s2 = s1 + len(b"_OBJC_CLASS_$_CADisplayLink\0"); s3 = s2 + len(b"_OBJC_CLASS_$_MyGame\0")
    nlist = struct.pack("<IBBHQ", s1, 0x01, 0, 0, 0) + struct.pack("<IBBHQ", s2, 0x0f, 1, 0, 0x1000) + struct.pack("<IBBHQ", s3, 0x01, 0, 0, 0)
    funcs = bytes([0x10, 0x20, 0x30, 0x40, 0x00, 0x00, 0x00, 0x00])

    lib = b"/System/Library/Frameworks/Metal.framework/Metal\0"
    lib_cmd_size = (24 + len(lib) + 7) // 8 * 8
    seg_size = 72 + 80
    cmds_size = seg_size + 24 + lib_cmd_size + 24 + 24 + 24 + 16
    ncmds = 7
    data_off = 32 + cmds_size
    cstr_off = data_off
    sym_off = cstr_off + len(cstring)
    sym_off += (-sym_off) % 8
    str_off = sym_off + len(nlist)
    fn_off = str_off + len(strtab)

    out = bytearray()
    out += struct.pack("<IiiIIIII", 0xfeedfacf, 0x0100000C, 0, 2, ncmds, cmds_size, 0, 0)
    seg = struct.pack("<II16sQQQQiiII", 0x19, seg_size, b"__TEXT", 0, 0x4000, 0, 0x4000, 5, 5, 1, 0)
    sec = struct.pack("<16s16sQQIIIIIIII", b"__cstring", b"__TEXT", 0x100, len(cstring), cstr_off, 0, 0, 0, 2, 0, 0, 0)
    out += seg + sec
    out += struct.pack("<IIIIII", 0x2, 24, sym_off, 3, str_off, len(strtab))
    out += struct.pack("<IIIIII", 0xC, lib_cmd_size, 24, 0, 0, 0)[:24] if False else b""
    dl = struct.pack("<IIIIII", 0xC, lib_cmd_size, 24, 0, 0, 0) + lib
    out += dl + b"\0" * (lib_cmd_size - len(dl))
    out += struct.pack("<IIQ", 0x2C, 24, 0)[:8] + struct.pack("<IIII", 0x4000, 0x1000, 1 if encrypted else 0, 0)
    out += struct.pack("<II", 0x32, 24) + struct.pack("<IIII", 2, 0x000F0000, 0x00110000, 0)[:16]
    out += struct.pack("<II", 0x1B, 24) + bytes(range(16))
    out += struct.pack("<IIII", 0x26, 16, fn_off, len(funcs))
    assert len(out) == 32 + cmds_size, (len(out), 32 + cmds_size)
    out += cstring
    out += b"\0" * (sym_off - len(out))
    out += nlist + strtab + funcs
    return bytes(out)

def build(path, encrypted=False):
    info = plistlib.dumps({
        "CFBundleIdentifier": "com.example.game", "CFBundleName": "Example Game", "CFBundleExecutable": "Example",
        "CFBundleShortVersionString": "1.2.3", "UIBackgroundModes": ["audio"], "MinimumOSVersion": "12.0",
        "NSCameraUsageDescription": "x"}, fmt=plistlib.FMT_BINARY)
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("Payload/Example.app/Info.plist", info, zipfile.ZIP_DEFLATED)
        z.writestr("Payload/Example.app/Example", macho(encrypted), zipfile.ZIP_DEFLATED)
        z.writestr("Payload/Example.app/Frameworks/UnityFramework.framework/UnityFramework", b"x" * 5000, zipfile.ZIP_STORED)
        z.writestr("Payload/Example.app/tex/a.png", b"p" * 2000, zipfile.ZIP_DEFLATED)

if __name__ == "__main__":
    build(sys.argv[1], encrypted=len(sys.argv) > 2 and sys.argv[2] == "enc")
