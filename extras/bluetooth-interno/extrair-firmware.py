"""Extrai o firmware do UWE5621 (wcnmodem.bin) do modulo do Android.

O Android da B13 nao traz wcnmodem.bin como arquivo: ele fica embutido na secao .data de
/vendor/lib/modules/uwe5621_bsp_sdio.ko, como imagem "WCNE" (ou "WCNM"). O cabecalho tem a
tabela de segmentos, entao o tamanho exato sai dela.

python3 extrair-firmware.py uwe5621_bsp_sdio.ko wcnmodem.bin
"""
import struct
import sys


def data_section(elf):
    assert elf[:4] == b"\x7fELF" and elf[4] == 2, "precisa de um ELF de 64 bits"
    shoff, = struct.unpack_from("<Q", elf, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", elf, 0x3A)
    sections = [struct.unpack_from("<IIQQQQIIQQ", elf, shoff + i * shentsize) for i in range(shnum)]
    names = sections[shstrndx]
    for name, _, _, _, offset, size, *_ in sections:
        label = elf[names[4] + name: elf.index(b"\0", names[4] + name)]
        if label == b".data":
            return elf[offset: offset + size]
    raise SystemExit("sem secao .data")


def main(source, target):
    data = data_section(open(source, "rb").read())
    for magic in (b"WCNE", b"WCNM"):
        start = data.find(magic)
        if start >= 0:
            break
    else:
        raise SystemExit("imagem WCNE/WCNM nao encontrada")
    image = data[start:]
    count, = struct.unpack_from("<I", image, 8)
    segments = [struct.unpack_from("<III", image, 12 + 12 * i) for i in range(count)]
    end = max(b + c for _, b, c in segments)  # o maior (offset + tamanho) entre os segmentos
    open(target, "wb").write(image[:end])
    version = image.find(b"Platform Version:")
    label = image[version: image.find(b"\0", version)].decode(errors="replace") if version >= 0 else "?"
    print(f"{target}: {end} bytes, {magic.decode()}, {count} segmentos, {label}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
