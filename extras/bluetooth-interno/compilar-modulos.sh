#!/bin/bash
# Compila os modulos do UWE5621DS (SDIO/BSP + tty do Bluetooth) para o kernel devmfc da B13.
# Roda num Debian arm64 (a propria B13 serve) como root:
#   bash compilar-modulos.sh linux-headers-6.18.40-meson64_*_arm64.deb [saida]
# O .deb de headers vem das releases do devmfc (mesma versao do `uname -r`).
# Driver: porte mainline do NullYing (GPL-2.0), no commit testado.
set -euo pipefail
HEADERS_DEB=$(realpath "$1")
OUT=$(realpath "${2:-modulos}")
DRIVER_REPO=https://github.com/NullYing/UWE5621DS-WIFI-Driver-For-Armbian.git
DRIVER_COMMIT=6a3db61eb1cdc2ae9af7571a9c4ccfe090a4e7bc
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    gcc-13 make bc flex bison libc6-dev libelf-dev libssl-dev git ca-certificates >/dev/null

# Headers num diretorio proprio (extrair em / quebra o /lib do merged-usr).
mkdir -p "$WORK/h" && dpkg -x "$HEADERS_DEB" "$WORK/h"
K=$(ls -d "$WORK"/h/usr/src/linux-headers-*)
# O pacote nao traz os geradores de arch/arm64/tools; os headers gerados ja estao la.
mkdir -p "$K/arch/arm64/tools"
for f in gen-cpucaps.awk cpucaps gen-sysreg.awk sysreg; do
    [ -e "$K/arch/arm64/tools/$f" ] || { : > "$K/arch/arm64/tools/$f"; touch -d 2000-01-01 "$K/arch/arm64/tools/$f"; }
done
cp "$K/include/generated/utsrelease.h" "$WORK/utsrelease.h"
make -C "$K" CC=gcc-13 HOSTCC=gcc-13 -j"$(nproc)" modules_prepare >/dev/null 2>&1 || true
# modules_prepare tira o sufixo -meson64; sem ele o vermagic nao bate e o insmod recusa.
cp "$WORK/utsrelease.h" "$K/include/generated/utsrelease.h"
test -x "$K/scripts/mod/modpost" && test -x "$K/scripts/basic/fixdep"

git clone -q "$DRIVER_REPO" "$WORK/drv" && git -C "$WORK/drv" checkout -q "$DRIVER_COMMIT"
# O porte deixou dois printk(KERN_ERR "DBG: ... dispatch") por pacote SDIO: inundam o console e o
# log do kernel (e custam CPU no console do framebuffer). Remove os dois.
sed -i -E 's/printk\(KERN_ERR "DBG: (TX|RX) dispatch[^;]*\);[[:space:]]*//' "$WORK/drv/unisocwcn/sdio/sdiohal_common.c"
! grep -q 'DBG: [TR]X dispatch' "$WORK/drv/unisocwcn/sdio/sdiohal_common.c"
M="make -C $K CC=gcc-13 HOSTCC=gcc-13 ARCH=arm64"
# BSP: variante Amlogic do UWE5621; o firmware vem de /lib/firmware/wcnmodem.bin.
(cd "$WORK/drv/unisocwcn" && $M M="$PWD" CFG_AML_WIFI_DEVICE_UWE5621=y modules)
# tty do BT: OTT_UWE registra o proprio platform device (sem no sprd,mtty no DTB) -> /dev/ttyBT0.
(cd "$WORK/drv/tty-sdio" && UNISOC_BSP_INCLUDE="$WORK/drv/unisocwcn/include" \
    KBUILD_EXTRA_SYMBOLS="$WORK/drv/unisocwcn/Module.symvers" \
    $M M="$PWD" CONFIG_TTY_OVERY_SDIO=m CONFIG_RK_WIFI_DEVICE_UWE5622=y KCFLAGS=-DOTT_UWE modules)
mkdir -p "$OUT"
cp "$WORK/drv/unisocwcn/uwe5621_bsp_sdio.ko" "$WORK/drv/tty-sdio/sprdbt_tty.ko" "$OUT/"
for k in "$OUT"/*.ko; do echo "$k: $(strings "$k" | grep -m1 '^vermagic=')"; done
