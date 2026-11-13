#!/bin/bash
# BTV B13 internal Bluetooth (Unisoc UWE5621DS / Marlin3E over SDIO) for mainline 6.18.
#  1. uwe5621_bsp_sdio + sprdbt_tty (NullYing's mainline port, OTT_UWE build) -> /dev/ttyBT0
#  2. rfkill "bluetooth" unblock powers the chip and uploads /lib/firmware/wcnmodem.bin
#     (Android's W22.10.2 image; needs the SDIO bus at 150 MHz -- see the b13 DTB)
#  3. unisoc-btinit: Android libbt-vendor's 0xFCA0 pskey, 0xFCA2 RF, 0xFCA1 enable
#  4. unisoc-hciproxy hides the advertised-but-broken Read Default Link Policy command
#  5. btattach (foreground: this service's main process) hands the pty to the kernel as H:4
set -u
D=/usr/local/lib/b13-bt
lsmod | grep -q uwe5621_bsp_sdio || insmod $D/uwe5621_bsp_sdio.ko || exit 1
lsmod | grep -q sprdbt_tty || insmod $D/sprdbt_tty.ko || exit 1
for i in $(seq 1 20); do [ -e /dev/ttyBT0 ] && break; sleep 0.5; done
for r in /sys/class/rfkill/rfkill*; do [ "$(cat $r/name)" = bluetooth ] && echo 0 > $r/soft; done
sleep 8 # firmware download + CP2 boot
$D/unisoc-btinit /dev/ttyBT0 $D/pskey.bin $D/rf.bin || exit 1
$D/unisoc-hciproxy /dev/ttyBT0 /run/unisoc-bt.pty &
sleep 1
# Once the kernel registers the controller, lift its rfkill soft block (Pi OS/Debian start blocked).
( for i in $(seq 1 30); do sleep 1
    for r in /sys/class/rfkill/rfkill*; do case "$(cat $r/name)" in hci*) [ "$(cat $r/soft)" = 1 ] && echo 0 > $r/soft && done=1;; esac; done
    [ "${done:-0}" = 1 ] && { bluetoothctl power on >/dev/null 2>&1; break; }
  done ) &
exec btattach -B /run/unisoc-bt.pty -P h4
