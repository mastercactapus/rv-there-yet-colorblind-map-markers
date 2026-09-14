#!/usr/bin/env python3
"""Wrap the inline compressed mip of a Zen UTexture2D asset in a .dds header.

UE stores the top mip's block data verbatim inside the .uasset when the texture
has no separate .ubulk. We don't parse the platform data properly -- we locate
the block data by offset and prepend a DDS header, which is enough for
ImageMagick to decode it.

The data is NOT reliably at the tail: some textures carry a few hundred bytes
after the pixels, so assuming "the last N bytes" silently decodes garbage.
Hence --offset auto, which finds the block alignment that makes horizontally
adjacent DXT blocks agree on their base color. Auto-detect resolves the offset
only to the nearest block (8 or 16 bytes), so the result can be translated by a
few pixels -- fine for inspecting colors, not for pixel-exact extraction.

Usage:
    ue_texture.py <file.uasset> <out.dds> [--format DXT5] [--size 512x512]
                  [--offset auto|tail|<int>]
"""

import argparse
import struct
import sys

# bytes per 4x4 block
BLOCK_BYTES = {"DXT1": 8, "DXT3": 16, "DXT5": 16, "BC4U": 8, "BC5U": 16, "BC7": 16}

DDSD_CAPS = 0x1
DDSD_HEIGHT = 0x2
DDSD_WIDTH = 0x4
DDSD_PIXELFORMAT = 0x1000
DDSD_LINEARSIZE = 0x80000
DDPF_FOURCC = 0x4
DDSCAPS_TEXTURE = 0x1000


def data_size(width, height, fmt):
    blocks = ((width + 3) // 4) * ((height + 3) // 4)
    return blocks * BLOCK_BYTES[fmt]


def dds_header(width, height, fmt, linear_size):
    fourcc = b"DX10" if fmt == "BC7" else fmt.encode("ascii")[:4]
    hdr = b"DDS "
    hdr += struct.pack(
        "<7I",
        124,
        DDSD_CAPS | DDSD_HEIGHT | DDSD_WIDTH | DDSD_PIXELFORMAT | DDSD_LINEARSIZE,
        height,
        width,
        linear_size,
        0,  # depth
        1,  # mip count
    )
    hdr += b"\0" * 44  # dwReserved1[11]
    # DDS_PIXELFORMAT
    hdr += struct.pack("<2I", 32, DDPF_FOURCC) + fourcc + b"\0" * 20
    hdr += struct.pack("<5I", DDSCAPS_TEXTURE, 0, 0, 0, 0)
    assert len(hdr) == 128, len(hdr)

    if fmt == "BC7":
        # DDS_HEADER_DXT10: DXGI_FORMAT_BC7_UNORM=98, D3D10_RESOURCE_DIMENSION_TEXTURE2D=3
        hdr += struct.pack("<5I", 98, 3, 0, 1, 0)
    return hdr


def find_offset(blob, width, height, fmt):
    """Pick the start offset whose DXT blocks look most like a real image.

    Correctly aligned block data has horizontally adjacent blocks agreeing
    closely on their first base color; misaligned data looks like noise.
    """
    stride = BLOCK_BYTES[fmt]
    blocks_per_row = (width + 3) // 4
    want = data_size(width, height, fmt)
    slack = len(blob) - want

    def score(off):
        total = count = 0
        for by in (blocks_per_row // 8, blocks_per_row // 4, blocks_per_row // 2):
            base = off + by * blocks_per_row * stride
            prev = None
            for bx in range(300):
                p = base + bx * stride
                # DXT1 stores colors first; DXT3/5 put them after the alpha block
                if fmt in ("DXT3", "DXT5"):
                    p += 8
                if p + 2 > len(blob):
                    return float("inf")
                c = struct.unpack_from("<H", blob, p)[0]
                cur = (((c >> 11) & 31) << 1, (c >> 5) & 63, (c & 31) << 1)
                if prev is not None:
                    total += sum(abs(a - b) for a, b in zip(cur, prev))
                    count += 1
                prev = cur
        return total / max(count, 1)

    best = min(range(slack + 1), key=score)
    return best, score(best)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("asset")
    ap.add_argument("out")
    ap.add_argument("--format", default="DXT5", choices=sorted(BLOCK_BYTES))
    ap.add_argument("--size", default="512x512")
    ap.add_argument(
        "--offset",
        default="auto",
        help="'auto' (detect block alignment), 'tail' (last N bytes), or a byte offset",
    )
    args = ap.parse_args()

    width, height = (int(v) for v in args.size.lower().split("x"))
    want = data_size(width, height, args.format)

    with open(args.asset, "rb") as fh:
        blob = fh.read()

    if len(blob) < want:
        print(
            f"asset is {len(blob)} bytes but {width}x{height} {args.format} "
            f"needs {want}; wrong size/format?",
            file=sys.stderr,
        )
        return 1

    if args.offset == "tail":
        start = len(blob) - want
    elif args.offset == "auto":
        start, sc = find_offset(blob, width, height, args.format)
        print(f"auto-detected block offset {start} (score {sc:.2f})", file=sys.stderr)
    else:
        start = int(args.offset)

    payload = blob[start:start + want]
    with open(args.out, "wb") as fh:
        fh.write(dds_header(width, height, args.format, want))
        fh.write(payload)

    print(
        f"{args.asset}: {want} bytes from offset {start} "
        f"({len(blob) - want - start} trailing bytes unused) -> {args.out}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
