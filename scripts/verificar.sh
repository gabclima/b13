#!/bin/bash
# =============================================================================
# verificar.sh -- confere se o env do eMMC foi gravado corretamente
# =============================================================================
# Rode DEPOIS da reinicializacao pelo pendrive, ANTES de remover o pendrive.
# Detecta a variante (pelo backup) e valida o alvo correto.
# =============================================================================

EMMC="/dev/mmcblk1"
BACKUP_DIR="/boot/amlboot-backups"
G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; N='\033[0m'

echo "================================================================"
echo "   Verificacao do env gravado no eMMC"
echo "================================================================"
echo

# variante (gravada pelo instalador)
VAR="?"
[[ -f "$BACKUP_DIR/variante.txt" ]] && VAR=$(cat "$BACKUP_DIR/variante.txt")
echo "Variante do firmware: $VAR"
echo

dd if="$EMMC" bs=512 skip=1875968 count=256 2>/dev/null | tr '\0' '\n' > /tmp/envdump.txt
BC=$(grep -a "^bootcmd=" /tmp/envdump.txt | head -1)
SEA=$(grep -a "^start_emmc_autoscript=" /tmp/envdump.txt | head -1)

echo "bootcmd gravado:"
echo "  ${BC:-<vazio>}"
echo "start_emmc_autoscript gravado:"
echo "  ${SEA:-<vazio>}"
echo

RESULT=1
if [[ "$VAR" == "A" ]]; then
    # variante A: o alvo e start_emmc_autoscript
    if echo "$SEA" | grep -q "fatload mmc 1:6"; then
        echo -e "${G}[ OK ] start_emmc_autoscript aponta para a factory. Deve bootar do eMMC.${N}"
        RESULT=0
    else
        echo -e "${R}[ERRO] start_emmc_autoscript nao ficou certo. Nao remova o pendrive.${N}"
    fi
else
    # variante B: o alvo e o bootcmd
    if echo "$BC" | grep -q "fatload mmc 1:6"; then
        echo -e "${G}[ OK ] bootcmd aponta para a factory. Deve bootar do eMMC.${N}"
        RESULT=0
    elif echo "$BC" | grep -q "cmd_boot_get_order"; then
        echo -e "${R}[ERRO] bootcmd ficou com o multiboot do devmfc (env poluido).${N}"
        echo -e "${R}       Nao remova o pendrive. Me mande esta saida.${N}"
    elif echo "$BC" | grep -q "^bootcmd=run storeboot$"; then
        echo -e "${Y}[----] bootcmd ainda e o original. O patch nao rodou.${N}"
        echo -e "${Y}       O aml_autoscript foi mesmo carregado no boot pelo pendrive?${N}"
    else
        echo -e "${Y}[????] bootcmd em estado inesperado. Nao remova o pendrive.${N}"
    fi
fi

echo
echo "--- Sistema no eMMC ---"
mkdir -p /mnt/chk 2>/dev/null
if mount "${EMMC}p1" /mnt/chk 2>/dev/null; then
    ls /mnt/chk/vmlinuz-* >/dev/null 2>&1 && echo "  kernel: OK" || echo "  kernel: FALTANDO"
    [[ -f /mnt/chk/bootscript ]] && echo "  bootscript: OK" || echo "  bootscript: FALTANDO"
    umount /mnt/chk
else
    echo "  nao consegui montar ${EMMC}p1"
fi

echo "--- emmc_autoscript na factory ---"
mkdir -p /mnt/fac 2>/dev/null
if mount -t vfat -o loop,offset=1029701632,sizelimit=8388608 "$EMMC" /mnt/fac 2>/dev/null; then
    [[ -f /mnt/fac/emmc_autoscript ]] && echo "  emmc_autoscript: OK ($(stat -c%s /mnt/fac/emmc_autoscript) bytes)" || echo "  emmc_autoscript: FALTANDO"
    umount /mnt/fac
else
    echo "  nao consegui montar a factory"
fi

echo
if [[ $RESULT -eq 0 ]]; then
    echo -e "${G}Tudo certo. Pode desligar, remover o pendrive e ligar.${N}"
else
    echo -e "${Y}Nao remova o pendrive ainda. Me mande esta saida.${N}"
fi
