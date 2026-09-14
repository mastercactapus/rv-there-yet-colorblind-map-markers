#!/usr/bin/env python3
"""List the contents of a UE5 IoStore .utoc container.

Only parses the header + directory index, which are stored uncompressed, so this
works without Oodle. Useful for finding asset paths before doing a real extract.

Usage:
    utoc_index.py <file.utoc> [substring-filter ...]
"""

import struct
import sys

MAGIC = b"-==--==--==--==-"

# EIoContainerFlags
FLAG_COMPRESSED = 0x1
FLAG_ENCRYPTED = 0x2
FLAG_SIGNED = 0x4
FLAG_INDEXED = 0x8
FLAG_ONDEMAND = 0x10


class Reader:
    def __init__(self, buf, pos=0):
        self.buf = buf
        self.pos = pos

    def take(self, n):
        out = self.buf[self.pos:self.pos + n]
        if len(out) != n:
            raise EOFError(f"wanted {n} bytes at {self.pos}, got {len(out)}")
        self.pos += n
        return out

    def u32(self):
        return struct.unpack_from("<I", self.take(4))[0]

    def i32(self):
        return struct.unpack_from("<i", self.take(4))[0]

    def fstring(self):
        """UE FString: int32 length. Negative => UTF-16. Length includes NUL."""
        n = self.i32()
        if n == 0:
            return ""
        if n < 0:
            raw = self.take(-n * 2)
            return raw.decode("utf-16-le").rstrip("\0")
        raw = self.take(n)
        return raw.decode("utf-8", errors="replace").rstrip("\0")

    def array(self, elem_size):
        count = self.u32()
        return self.take(count * elem_size), count


def parse_header(buf):
    if buf[:16] != MAGIC:
        raise ValueError("not a .utoc file (bad magic)")
    (version,) = struct.unpack_from("<B", buf, 0x10)
    fields = struct.unpack_from("<9I", buf, 0x14)
    (header_size, entry_count, cblock_count, cblock_size,
     cmethod_count, cmethod_len, block_size, dir_index_size, partition_count) = fields
    container_id = struct.unpack_from("<Q", buf, 0x38)[0]
    enc_guid = buf[0x40:0x50]
    flags = struct.unpack_from("<B", buf, 0x50)[0]
    perfect_hash_seeds = struct.unpack_from("<I", buf, 0x54)[0]
    partition_size = struct.unpack_from("<Q", buf, 0x58)[0]
    without_hash = struct.unpack_from("<I", buf, 0x60)[0]
    return dict(
        version=version, header_size=header_size, entry_count=entry_count,
        cblock_count=cblock_count, cblock_size=cblock_size,
        cmethod_count=cmethod_count, cmethod_len=cmethod_len,
        block_size=block_size, dir_index_size=dir_index_size,
        partition_count=partition_count, container_id=container_id,
        enc_guid=enc_guid, flags=flags, perfect_hash_seeds=perfect_hash_seeds,
        partition_size=partition_size, without_hash=without_hash,
    )


def directory_index_offset(h):
    """Byte offset of the directory index blob within the .utoc."""
    off = h["header_size"]
    off += h["entry_count"] * 12          # FIoChunkId[]
    off += h["entry_count"] * 10          # FIoOffsetAndLength[]
    if h["version"] >= 4:                 # PerfectHash
        off += h["perfect_hash_seeds"] * 4
    if h["version"] >= 5:                 # PerfectHashWithOverflow
        off += h["without_hash"] * 4
    off += h["cblock_count"] * h["cblock_size"]
    off += h["cmethod_count"] * h["cmethod_len"]
    if h["flags"] & FLAG_SIGNED:
        raise NotImplementedError("signed container: signature block parsing not implemented")
    return off


def chunk_ids(buf, h):
    """FIoChunkId[] sits immediately after the header; 12 bytes each."""
    base = h["header_size"]
    return [buf[base + i * 12: base + i * 12 + 12] for i in range(h["entry_count"])]


def parse_directory_index(blob):
    r = Reader(blob)
    mount_point = r.fstring()

    dirs_raw, ndirs = r.array(16)
    files_raw, nfiles = r.array(12)

    nstrings = r.u32()
    strings = [r.fstring() for _ in range(nstrings)]

    dirs = [struct.unpack_from("<4I", dirs_raw, i * 16) for i in range(ndirs)]
    files = [struct.unpack_from("<3I", files_raw, i * 12) for i in range(nfiles)]

    NONE = 0xFFFFFFFF
    out = []

    def name_of(idx):
        return strings[idx] if idx != NONE else ""

    def walk(dir_idx, prefix):
        while dir_idx != NONE:
            name, first_child, next_sibling, first_file = dirs[dir_idx]
            path = prefix if name == NONE else f"{prefix}{name_of(name)}/"

            file_idx = first_file
            while file_idx != NONE:
                fname, next_file, user_data = files[file_idx]
                out.append((path + name_of(fname), user_data))
                file_idx = next_file

            if first_child != NONE:
                walk(first_child, path)
            dir_idx = next_sibling

    if ndirs:
        walk(0, "")
    return mount_point, out


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 1

    path = sys.argv[1]
    filters = [f.lower() for f in sys.argv[2:]]

    with open(path, "rb") as fh:
        buf = fh.read()

    h = parse_header(buf)
    flags = h["flags"]
    flag_names = [n for bit, n in (
        (FLAG_COMPRESSED, "Compressed"), (FLAG_ENCRYPTED, "Encrypted"),
        (FLAG_SIGNED, "Signed"), (FLAG_INDEXED, "Indexed"),
        (FLAG_ONDEMAND, "OnDemand"),
    ) if flags & bit]

    print(f"# {path}", file=sys.stderr)
    print(f"#   toc version      : {h['version']}", file=sys.stderr)
    print(f"#   chunks           : {h['entry_count']}", file=sys.stderr)
    print(f"#   container id     : {h['container_id']:016x}", file=sys.stderr)
    print(f"#   flags            : {flags:#x} ({'|'.join(flag_names) or 'none'})", file=sys.stderr)
    print(f"#   compression block: {h['block_size']}", file=sys.stderr)

    if not flags & FLAG_INDEXED:
        print("# container has no directory index; nothing to list", file=sys.stderr)
        return 2

    off = directory_index_offset(h)
    blob = buf[off:off + h["dir_index_size"]]
    mount_point, entries = parse_directory_index(blob)

    print(f"#   mount point      : {mount_point}", file=sys.stderr)
    print(f"#   files            : {len(entries)}", file=sys.stderr)

    ids = chunk_ids(buf, h)

    shown = 0
    for fpath, user_data in sorted(entries):
        full = mount_point + fpath
        if filters and not all(f in full.lower() for f in filters):
            continue
        cid = ids[user_data].hex() if user_data < len(ids) else "?" * 24
        print(f"{user_data}\t{cid}\t{full}")
        shown += 1
    print(f"# listed {shown} file(s)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
