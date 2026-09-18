#!/usr/bin/env python3
"""Crops a region out of a PNG and enlarges it.

It exists for inspecting interface details: icon alignment, border widths,
padding. On a 1280x800 screenshot a 36-pixel-tall panel cannot be judged by
eye, and a browser image viewer cannot crop a region.

    zoom-shot.py in.png out.png X Y W H [scale]

No dependencies: the PNG is parsed and rebuilt by hand through zlib.
"""
import sys, zlib, struct


def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat, hdr = 8, bytearray(), None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if ctype == b"IHDR":
            hdr = struct.unpack(">IIBBBBB", body)
        elif ctype == b"IDAT":
            idat += body
        elif ctype == b"IEND":
            break
        pos += 12 + length
    w, h, depth, color, _, _, interlace = hdr
    assert depth == 8 and interlace == 0, "only 8-bit non-interlaced images are supported"
    nch = {0: 1, 2: 3, 4: 2, 6: 4}[color]
    raw = zlib.decompress(bytes(idat))

    # Undo the per-scanline PNG filters.
    stride = w * nch
    out = bytearray(h * stride)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if f == 1:
            for i in range(nch, stride):
                line[i] = (line[i] + line[i - nch]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                b = prev[i]
                c = prev[i - nch] if i >= nch else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, nch, out


def write_png(path, w, h, nch, pix):
    color = {1: 0, 2: 4, 3: 2, 4: 6}[nch]
    raw = bytearray()
    stride = w * nch
    for y in range(h):
        raw.append(0)
        raw += pix[y * stride:(y + 1) * stride]

    def chunk(t, d):
        return (struct.pack(">I", len(d)) + t + d
                + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, color, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
           + chunk(b"IEND", b""))
    open(path, "wb").write(png)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    x, y, cw, ch = (int(v) for v in sys.argv[3:7])
    scale = int(sys.argv[7]) if len(sys.argv) > 7 else 6

    w, h, nch, pix = read_png(src)
    cw, ch = min(cw, w - x), min(ch, h - y)
    stride = w * nch

    ow, oh = cw * scale, ch * scale
    out = bytearray(ow * oh * nch)
    for j in range(ch):
        row = bytearray()
        base = (y + j) * stride + x * nch
        for i in range(cw):
            px = pix[base + i * nch: base + (i + 1) * nch]
            row += px * scale
        for k in range(scale):
            o = ((j * scale + k) * ow) * nch
            out[o:o + len(row)] = row

    write_png(dst, ow, oh, nch, out)
    print("%s: %dx%d -> %dx%d (x%d)" % (dst, cw, ch, ow, oh, scale))


main()
