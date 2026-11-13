"""Serialize Unisoc Marlin3 Bluetooth config .ini files (bt_configure_pskey.ini / _rf.ini)
into the byte blocks Android's libbt-vendor_uwe.so sends with HCI vendor commands
0xFCA0 (pskey) and 0xFCA2 (RF).

Each field is preceded by a "#[x.yy]__/L=<bytes>" comment; a field's values share its
length equally (L/count bytes each) and are little-endian, as libbt-vendor writes them.

python3 -I unisoc_ini2bin.py in.ini out.bin [--addr AA:BB:CC:DD:EE:FF]
"""
import re
import sys


def serialize(path, address=None):
    length = None
    out = bytearray()
    total = None
    for line in open(path):
        line = line.strip()
        header = re.search(r"\[Total Length=(\d+)\]", line)
        if header and total is None:
            total = int(header.group(1))
        size = re.match(r"#\[[0-9.]+\]__/L=(\d+)", line)
        if size:
            length = int(size.group(1))
            continue
        if line.startswith("#") or "=" not in line or length is None:
            continue
        name, values = (part.strip() for part in line.split("=", 1))
        numbers = [int(v.strip(), 0) for v in values.split(",") if v.strip()]
        if name == "device_addr" and address:
            # libbt stores the BD_ADDR least-significant byte first.
            numbers = list(reversed([int(b, 16) for b in address.split(":")]))
        width = length // len(numbers)
        assert width * len(numbers) == length, f"{name}: {length} bytes for {len(numbers)} values"
        for number in numbers:
            out += number.to_bytes(width, "little")
        length = None
    return bytes(out), total


def main():
    address = sys.argv[sys.argv.index("--addr") + 1] if "--addr" in sys.argv else None
    data, total = serialize(sys.argv[1], address)
    assert total is None or len(data) == total, f"serialized {len(data)} bytes, header says {total}"
    open(sys.argv[2], "wb").write(data)
    print(f"{sys.argv[2]}: {len(data)} bytes (header total {total})")


if __name__ == "__main__":
    main()
