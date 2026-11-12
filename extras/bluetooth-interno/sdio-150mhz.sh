#!/bin/bash
# Limita o SDIO do UWE5621 a 150 MHz, como o DTB do Android (max-frequency = <0x8f0d180>).
# Com os 200 MHz do DTB generico o download do firmware falha com erro CRC (-84).
# Roda na B13 como root; guarda o original em .orig.
set -euo pipefail
D=$(ls /boot/dtb-$(uname -r)/amlogic/meson-sc2-ah212-generic.dtb)
command -v fdtput >/dev/null || apt-get install -y -qq device-tree-compiler
[ -f "$D.orig" ] || cp "$D" "$D.orig"
fdtput -t x "$D" /soc/mmc@fe088000 max-frequency 8f0d180
echo "$D: SDIO max-frequency = $(fdtget -t x "$D" /soc/mmc@fe088000 max-frequency) (reinicie)"
