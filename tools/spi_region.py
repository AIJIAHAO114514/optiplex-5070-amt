#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
spi_region.py - Intel SPI flash image / descriptor helper
(ASCII-only output on purpose: it must survive any OEM cmd codepage)

Commands
  info      <image>                        show flash descriptor region table + image hash
  extract   <image> <region> <out.bin>     cut one region out of a full SPI image
  check-me  <me.bin>                       sanity check a ME region file ($FPT magic, size, hash)
  compare   <imgA> <imgB>                  per-region SHA256 diff (use before flashing!)
  desc      <image>                        dump raw FLMAP/FLREG values (debug)

Region index: 0=Descriptor 1=BIOS 2=ME 3=GbE 4=PDR 5=DevExp 6-7=reserved

Exit codes: 0 ok, 2 usage/IO, 3 parse failure, 4 check failure
"""

import hashlib
import io
import os
import struct
import sys

REGION_NAMES = {
    0: "Descriptor",
    1: "BIOS",
    2: "ME",
    3: "GbE",
    4: "PDR",
    5: "DevExp",
    6: "Region6",
    7: "Region7",
}

DESC_SIG = bytes.fromhex("ffffffff" "00000000" "5aa5")


def read_file(path):
    with open(path, "rb") as f:
        return f.read()


def u32(buf, off):
    return struct.unpack_from("<I", buf, off)[0]


def human(n):
    if n >= 1024 * 1024:
        return "%.2f MB" % (n / 1024.0 / 1024.0)
    return "%d KB" % (n // 1024)


def parse_descriptor(img):
    """Return dict with flmap0, frba, regions{idx:(base,size,present)}."""
    if len(img) < 0x1000:
        raise ValueError("image too small to contain a flash descriptor")

    flmap0 = u32(img, 0x14)
    frba = (flmap0 >> 16) & 0xFF       # region base address, 16-byte units
    fcba = flmap0 & 0xFF               # component base address, 16-byte units
    nr = ((flmap0 >> 24) & 0x07) + 1   # number of regions (informational)

    reg_off = frba * 0x10
    if reg_off == 0 or reg_off + 4 > 0x1000:
        raise ValueError("implausible FRBA 0x%X (descriptor not recognised)" % frba)

    regions = {}
    for idx in range(8):
        off = reg_off + idx * 4
        if off + 4 > 0x1000:
            break
        val = u32(img, off)
        if val == 0xFFFFFFFF:
            regions[idx] = (0, 0, False)
            continue
        base = (val & 0x7FFF) * 0x1000
        limit = ((val >> 16) & 0x7FFF) * 0x1000 + 0xFFF
        # "absent" marker used by Intel: unprogrammed fields read back as 0x7FFF
        if (val & 0x7FFF) == 0x7FFF or ((val >> 16) & 0x7FFF) == 0x7FFF:
            regions[idx] = (0, 0, False)
            continue
        if limit < base:
            regions[idx] = (0, 0, False)
            continue
        regions[idx] = (base, limit - base + 1, True)

    return {
        "flmap0": flmap0,
        "frba": frba,
        "fcba": fcba,
        "nr": nr,
        "reg_off": reg_off,
        "regions": regions,
    }


def sha256(buf):
    return hashlib.sha256(buf).hexdigest()


def md5(buf):
    return hashlib.md5(buf).hexdigest()


def print_table(img, desc):
    print("Image        : %d bytes (%s)" % (len(img), human(len(img))))
    print("Descriptor   : FLMAP0=0x%08X  FRBA=0x%X (table @0x%03X)  FCBA=0x%X  NR=%d"
          % (desc["flmap0"], desc["frba"], desc["reg_off"], desc["fcba"], desc["nr"]))
    print("")
    print("  idx  region        base         size         end          status")
    print("  ---  ------------  -----------  -----------  -----------  --------")
    for idx in sorted(desc["regions"]):
        base, size, present = desc["regions"][idx]
        name = REGION_NAMES.get(idx, "Region%d" % idx)
        if not present:
            print("  %-3d  %-12s  %-11s  %-11s  %-11s  absent" % (idx, name, "-", "-", "-"))
            continue
        status = "ok"
        if base + size > len(img):
            status = "OUT OF IMAGE RANGE"
        print("  %-3d  %-12s  0x%08X   0x%08X   0x%08X    %s"
              % (idx, name, base, size, base + size - 1, status))
    print("")
    print("Image SHA256 : %s" % sha256(img))
    print("Image MD5    : %s" % md5(img))


def cmd_info(args):
    if len(args) < 1:
        return 2
    path = args[0]
    img = read_file(path)
    try:
        desc = parse_descriptor(img)
    except ValueError as e:
        print("ERROR: %s" % e)
        print("       The file does not look like a full SPI/BIOS dump.")
        return 3
    print("File         : %s" % os.path.abspath(path))
    print_table(img, desc)
    # machine readable tail
    for idx, (base, size, present) in sorted(desc["regions"].items()):
        if present:
            print("RESULT %s_OFFSET=0x%X %s_SIZE=0x%X"
                  % (REGION_NAMES[idx].upper(), base, REGION_NAMES[idx].upper(), size))
    return 0


def cmd_dump_desc(args):
    if len(args) < 1:
        return 2
    img = read_file(args[0])
    desc = parse_descriptor(img)
    print("bytes 0x00-0x0F: %s" % img[0:16].hex())
    print("FLVAL0 0x10 = 0x%08X" % u32(img, 0x10))
    print("FLMAP0 0x14 = 0x%08X" % u32(img, 0x14))
    print("FLMAP1 0x18 = 0x%08X" % u32(img, 0x18))
    print("FLMAP2 0x1C = 0x%08X" % u32(img, 0x1C))
    print("FLCOMP 0x20 = 0x%08X" % u32(img, 0x20))
    print("FRBA table @ 0x%03X" % desc["reg_off"])
    for idx in range(8):
        off = desc["reg_off"] + idx * 4
        print("  FLREG%d @0x%03X = 0x%08X" % (idx, off, u32(img, off)))
    return 0


def resolve_region(name):
    name = name.strip().lower()
    for idx, rname in REGION_NAMES.items():
        if rname.lower() == name:
            return idx
    if name.isdigit():
        return int(name)
    raise ValueError("unknown region '%s'" % name)


def cmd_extract(args):
    if len(args) < 3:
        print("usage: extract <image> <region> <out.bin>")
        return 2
    img_path, region_name, out_path = args[0], args[1], args[2]
    img = read_file(img_path)
    desc = parse_descriptor(img)
    idx = resolve_region(region_name)
    if idx not in desc["regions"] or not desc["regions"][idx][2]:
        print("ERROR: region %s is not present in this image" % region_name)
        return 4
    base, size, _ = desc["regions"][idx]
    if base + size > len(img):
        print("ERROR: region extends past end of file (file truncated?)")
        return 4
    data = img[base:base + size]
    with open(out_path, "wb") as f:
        f.write(data)
    print("Region       : %s (idx %d)" % (REGION_NAMES.get(idx, "?"), idx))
    print("Offset       : 0x%08X" % base)
    print("Size         : 0x%08X (%d bytes, %s)" % (size, size, human(size)))
    print("Written      : %s" % os.path.abspath(out_path))
    print("SHA256       : %s" % sha256(data))
    return 0


def cmd_check_me(args):
    if len(args) < 1:
        return 2
    path = args[0]
    data = read_file(path)
    ok = True
    print("File         : %s" % os.path.abspath(path))
    print("Size         : %d bytes (%s)" % (len(data), human(len(data))))
    print("SHA256       : %s" % sha256(data))
    # 真机的 ME 区常带前置 0xFF 填充（5070 是 0x1000 字节），$FPT 不一定在 0 偏移
    window = data[:0x20000]
    fpt_off = window.find(b"$FPT")
    if fpt_off < 0:
        fpt_off = data.find(b"$FPT")
    if fpt_off >= 0:
        print("Magic        : $FPT at offset 0x%X  (valid CSME region image)" % fpt_off)
        if fpt_off:
            print("Padding      : 前面 %d 字节 0xFF 填充，属正常" % fpt_off)
    elif data[:4] == b"$CPD":
        print("Magic        : $CPD at offset 0  (valid ME region image, no FPT header)")
    elif all(b == 0xff for b in data[:0x1000]):
        print("Magic        : 前 4KB 全是 0xFF，这个文件是空的（读失败或不是 ME 区）")
        ok = False
    else:
        print("Magic        : %s 且找不到 $FPT（NOT a ME region image）" % data[:4].hex())
        ok = False
    # a couple of cheap structural hints
    if b"$MN2" in data[:0x100000]:
        print("Manifest     : $MN2 found")
    if b"FTPR" in data[:0x100000]:
        print("Code module  : FTPR found")
    print("RESULT ME_SIZE=%d" % len(data))
    return 0 if ok else 4


def region_list(img):
    desc = parse_descriptor(img)
    out = []
    for idx in sorted(desc["regions"]):
        base, size, present = desc["regions"][idx]
        if present and base + size <= len(img):
            out.append((idx, REGION_NAMES[idx], base, size))
    return out


def cmd_compare(args):
    ignore = set()
    files = []
    for a in args:
        if a in ("--ignore-me", "-x"):
            ignore.add(2)
        elif a == "--ignore-desc":
            ignore.add(0)
        elif a.startswith("--ignore="):
            ignore.add(resolve_region(a.split("=", 1)[1]))
        else:
            files.append(a)
    if len(files) < 2:
        print("usage: compare <imgA> <imgB> [--ignore-me] [--ignore-desc]")
        return 2
    a = read_file(files[0])
    b = read_file(files[1])
    print("A: %s (%d bytes)" % (os.path.abspath(files[0]), len(a)))
    print("B: %s (%d bytes)" % (os.path.abspath(files[1]), len(b)))
    if len(a) != len(b):
        print("WARNING: size differs (A=%d B=%d)" % (len(a), len(b)))
    try:
        ra = {i: (n, base, size) for i, n, base, size in region_list(a)}
    except ValueError as e:
        print("ERROR: %s" % e)
        return 3
    rc = 0
    print("")
    print("  region        offset       size         A==B?")
    print("  ------------  -----------  -----------  -----")
    for idx in sorted(ra):
        name, base, size = ra[idx]
        da = a[base:base + size]
        db = b[base:base + size] if base + size <= len(b) else b""
        # 描述符 0x20-0x2F 是 FLILL（硬件记录的非法指令日志），不是配置位。
        # FIT 每次 Build 都会把它清零，属正常现象；忽略并单独说明。
        note = ""
        if name == "Descriptor" and len(da) >= 0x30 and len(db) >= 0x30 and da != db:
            da2, db2 = bytearray(da), bytearray(db)
            fa = bytes(da2[0x20:0x30]); fb = bytes(db2[0x20:0x30])
            da2[0x20:0x30] = b"\x00" * 16
            db2[0x20:0x30] = b"\x00" * 16
            if bytes(da2) == bytes(db2):
                note = "  (FLILL log %s -> %s, harmless)" % (fa.hex(), fb.hex())
                da, db = bytes(da2), bytes(db2)
        same = da == db
        tag = "same" if same else "DIFFERENT"
        if idx in ignore:
            tag += " (ignored)"
            if not same:
                offs = [i for i in range(len(da)) if da[i] != db[i]]
                note = "  differs in %d bytes @ %s (not written, ignored)" % (
                    len(offs), ", ".join("0x%X" % o for o in offs[:6]) + (" ..." if len(offs) > 6 else ""))
        elif not same:
            rc = 4
        print("  %-12s  0x%08X   0x%08X   %s%s" % (name, base, size, tag, note))
        if not same and db:
            # first difference
            n = min(len(da), len(db))
            for i in range(n):
                if da[i] != db[i]:
                    print("      first diff at image offset 0x%08X (A=0x%02X B=0x%02X)"
                          % (base + i, da[i], db[i]))
                    break
    print("")
    if rc == 0:
        print("RESULT %s" % ("IDENTICAL" if not ignore else "IDENTICAL-EXCEPT-IGNORED"))
    else:
        print("RESULT DIFFERS")
    return rc


def cmd_check_pair(args):
    """compare descriptor-sliced ME region against an fpt -me -d dump"""
    if len(args) < 2:
        print("usage: check-pair <full_image> <me_from_fpt.bin>")
        return 2
    img = read_file(args[0])
    me = read_file(args[1])
    desc = parse_descriptor(img)
    if 2 not in desc["regions"] or not desc["regions"][2][2]:
        print("ERROR: ME region not present in the image descriptor")
        return 4
    base, size, _ = desc["regions"][2]
    sliced = img[base:base + size]
    print("")
    print("Cross-check  : descriptor slice vs fpt -me -d dump")
    print("Descriptor   : ME at 0x%08X, %d bytes" % (base, size))
    print("fpt dump     : %d bytes" % len(me))
    if len(me) != size:
        print("RESULT SIZE-MISMATCH  descriptor=%d fpt=%d (diff %d)"
              % (size, len(me), len(me) - size))
        return 4
    if sliced == me:
        print("RESULT MATCH  both are byte-identical")
        return 0
    n = min(len(sliced), len(me))
    for i in range(n):
        if sliced[i] != me[i]:
            print("first diff at ME offset 0x%06X (descriptor=0x%02X fpt=0x%02X)"
                  % (i, sliced[i], me[i]))
            break
    print("RESULT CONTENT-MISMATCH")
    return 4


USAGE = __doc__


def main(argv):
    if len(argv) < 2:
        print(USAGE)
        return 2
    cmd = argv[1].lower()
    args = argv[2:]
    handlers = {
        "info": cmd_info,
        "desc": cmd_dump_desc,
        "extract": cmd_extract,
        "check-me": cmd_check_me,
        "check-pair": cmd_check_pair,
        "compare": cmd_compare,
    }
    if cmd in ("-h", "--help", "help"):
        print(USAGE)
        return 0
    if cmd not in handlers:
        print("unknown command '%s'" % cmd)
        print(USAGE)
        return 2
    try:
        return handlers[cmd](args)
    except FileNotFoundError as e:
        print("ERROR: file not found: %s" % e.filename)
        return 2
    except PermissionError as e:
        print("ERROR: permission denied: %s" % e.filename)
        return 2
    except ValueError as e:
        print("ERROR: %s" % e)
        return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv))
