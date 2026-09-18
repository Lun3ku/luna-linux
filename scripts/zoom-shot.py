#!/usr/bin/env python3
"""Вырезает область из PNG и увеличивает её.

Нужен, чтобы разглядывать мелочи интерфейса: выравнивание значков,
толщину рамок, отступы. На скриншоте 1280x800 панель высотой 36 пикселей
на глаз не оценить, а браузерный просмотрщик вырезать область не умеет.

    zoom-shot.py вход.png выход.png X Y Ш В [масштаб]

Никаких зависимостей: PNG разбирается и собирается вручную через zlib.
"""
import sys, zlib, struct


def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "это не PNG"
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
    assert depth == 8 and interlace == 0, "поддерживаются только 8 бит без чересстрочности"
    nch = {0: 1, 2: 3, 4: 2, 6: 4}[color]
    raw = zlib.decompress(bytes(idat))

    # Снимаем построчные фильтры PNG.
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
