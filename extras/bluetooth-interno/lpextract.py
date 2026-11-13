"""Extract partitions from an Android dynamic-partition 'super' image (LP metadata v10.x).

python3 -I lpextract.py super.img outdir
Only LINEAR extents (the normal case for a flashed super image) are supported.
"""
import os
import struct
import sys

LP_METADATA_GEOMETRY_SIZE = 4096
LP_PARTITION_RESERVED_BYTES = 4096
SECTOR = 512


def main(image_path, out_dir):
    with open(image_path, "rb") as image:
        image.seek(LP_PARTITION_RESERVED_BYTES)
        geometry = image.read(LP_METADATA_GEOMETRY_SIZE)
        magic, struct_size = struct.unpack_from("<II", geometry, 0)
        assert magic == 0x616C4467, f"bad geometry magic {magic:#x}"
        metadata_max_size, slot_count, logical_block = struct.unpack_from("<III", geometry, 40)
        # Primary metadata, slot 0, follows the two geometry copies.
        base = LP_PARTITION_RESERVED_BYTES + 2 * LP_METADATA_GEOMETRY_SIZE
        image.seek(base)
        header = image.read(256)
        h_magic, major, minor, header_size = struct.unpack_from("<IHHI", header, 0)
        assert h_magic == 0x414C5030, f"bad metadata magic {h_magic:#x}"
        tables_size = struct.unpack_from("<I", header, 44)[0]
        # Table descriptors: partitions, extents, groups, block devices (offset, count, entry size).
        descriptors = [struct.unpack_from("<III", header, 80 + 12 * i) for i in range(4)]
        image.seek(base + header_size)
        tables = image.read(tables_size)
        p_off, p_count, p_size = descriptors[0]
        e_off, e_count, e_size = descriptors[1]
        extents = [struct.unpack_from("<QIQI", tables, e_off + i * e_size) for i in range(e_count)]
        os.makedirs(out_dir, exist_ok=True)
        for index in range(p_count):
            entry = tables[p_off + index * p_size: p_off + (index + 1) * p_size]
            name = entry[:36].rstrip(b"\0").decode()
            attributes, first_extent, num_extents, group = struct.unpack_from("<IIII", entry, 36)
            total = 0
            with open(os.path.join(out_dir, name + ".img"), "wb") as out:
                for extent in extents[first_extent:first_extent + num_extents]:
                    num_sectors, target_type, target_data, target_source = extent
                    if target_type != 0:  # 0 = LINEAR, 1 = ZERO
                        out.write(b"\0" * num_sectors * SECTOR)
                    else:
                        image.seek(target_data * SECTOR)
                        remaining = num_sectors * SECTOR
                        while remaining:
                            chunk = image.read(min(remaining, 64 << 20))
                            out.write(chunk)
                            remaining -= len(chunk)
                    total += num_sectors * SECTOR
            print(f"{name}: {total >> 20} MiB in {num_extents} extents")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
