#!/bin/bash
# =============================================================================
# instalar.sh -- AmlBoot: Debian no eMMC da BTV B13 (S905X4), 100% sem UART
# =============================================================================
# Instalador universal: detecta a variante de firmware vendor e aplica o
# metodo correto automaticamente. Funciona nas duas variantes conhecidas:
#
#   Variante A: bootcmd = "run start_autoscript; run storeboot"
#               (existe start_autoscript -> start_emmc_autoscript)
#               -> alvo: start_emmc_autoscript
#
#   Variante B: bootcmd = "run storeboot"
#               (NAO existe start_autoscript)
#               -> alvo: o proprio bootcmd
#
# Nos dois casos a gravacao do env e feita DE DENTRO do u-boot vendor, via
# patch no topo do aml_autoscript do pendrive (formato de env nativo). O
# fw_setenv do Linux NAO funciona nesta familia (env proprietario).
#
# COMO USAR:
#   1. Copie para a particao BOOT do pendrive (D: no Windows):
#        instalar.sh
#        emmc_autoscript.src
#   2. Boote o Debian live na B13. Login: root / tvbox
#   3. Rode:  bash /boot/instalar.sh
#   4. Responda 'y'. Ele instala tudo e prepara o pendrive.
#   5. Desligue, aperte UPDATE, ligue (reinicia pelo pendrive UMA vez).
#   6. No live, rode:  bash /boot/verificar.sh
#      Se der verde: desligue, REMOVA o pendrive, ligue -> Debian do eMMC.
# =============================================================================

set -uo pipefail

# ---- Constantes B13 (S905X4) -----------------------------------------------
EMMC="/dev/mmcblk1"
FACTORY_OFFSET=1029701632; FACTORY_SIZE=8388608   # factory / KEYBOX (mmc 1:6)
FACTORY_SKIP=2011136
ENV_SKIP=1875968; ENV_COUNT=16384                 # particao env (mmc 1:3)
HEADER_BYTES=72

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SELF_DIR/emmc_autoscript.src"
BOOT="/boot"
AML="$BOOT/aml_autoscript"
BACKUP_DIR="$BOOT/amlboot-backups"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; N='\033[0m'
say()  { echo -e "${B}[amlboot]${N} $*"; }
ok()   { echo -e "${G}[ ok ]${N} $*"; }
warn() { echo -e "${Y}[warn]${N} $*"; }
fail() { echo -e "${R}[err ]${N} $*"; echo -e "${R}ABORTADO.${N}"; exit 1; }

clear
echo "================================================================"
echo "   AmlBoot - Debian no eMMC da BTV B13 (100% sem UART)"
echo "   Instalador universal (detecta a variante do firmware)"
echo "================================================================"
echo

# =============================================================================
# 0. Pre-condicoes
# =============================================================================
[[ $EUID -eq 0 ]] || fail "Rode como root."
[[ -b "$EMMC" ]]  || fail "eMMC $EMMC nao encontrado. E mesmo uma B13?"
[[ -f "$SRC" ]]   || fail "Nao achei emmc_autoscript.src em $SELF_DIR."
[[ -f "$AML" ]]   || fail "Nao achei $AML. Esta particao BOOT e a do pendrive devmfc?"

ROOT_SRC=$(findmnt -no SOURCE / || true)
say "Live rodando de: ${ROOT_SRC:-?}"
[[ "$ROOT_SRC" == "$EMMC"* ]] && fail "Voce esta rodando do eMMC, nao do pendrive!"

# ---- Ferramentas (instala o que faltar; precisa de ethernet) ---------------
NEED=""
command -v parted    >/dev/null 2>&1 || NEED="$NEED parted"
command -v mkfs.vfat >/dev/null 2>&1 || NEED="$NEED dosfstools"
command -v mkfs.ext4 >/dev/null 2>&1 || NEED="$NEED e2fsprogs"
command -v rsync     >/dev/null 2>&1 || NEED="$NEED rsync"
command -v mkimage   >/dev/null 2>&1 || NEED="$NEED u-boot-tools"
if [[ -n "$NEED" ]]; then
    NEED=$(echo "$NEED" | tr ' ' '\n' | sort -u | tr '\n' ' ')
    say "Instalando ferramentas:$NEED (precisa de internet/ethernet)"
    apt-get update -qq || fail "apt-get update falhou. Conecte o cabo ethernet."
    apt-get install -y $NEED >/dev/null 2>&1 || fail "Falha instalando:$NEED"
fi
for t in parted mkfs.vfat mkfs.ext4 rsync blkid partprobe dd mkimage; do
    command -v "$t" >/dev/null 2>&1 || fail "Ferramenta '$t' ausente."
done
ok "Ferramentas prontas."

# ---- Compila o emmc_autoscript ---------------------------------------------
mkimage -C none -A arm -T script -d "$SRC" /tmp/emmc_autoscript >/dev/null \
    || fail "Falha compilando emmc_autoscript."
ok "emmc_autoscript compilado."

# ---- Le o texto do aml_autoscript (valida antes de mexer no eMMC) ----------
if [[ ! -f "$BOOT/aml_autoscript.devmfc-original" ]]; then
    cp "$AML" "$BOOT/aml_autoscript.devmfc-original"
fi
dd if="$BOOT/aml_autoscript.devmfc-original" of=/tmp/aml.txt bs=1 skip="$HEADER_BYTES" status=none \
    || fail "Falha extraindo texto do aml_autoscript."
grep -q "default_boot_order\|cmd_boot_emmc" /tmp/aml.txt \
    || fail "aml_autoscript nao parece o do devmfc. Abortei."
ok "aml_autoscript do pendrive lido e validado."

# =============================================================================
# 0.1 DETECTAR A VARIANTE do firmware vendor (le o env atual do eMMC)
# =============================================================================
say "Detectando a variante do firmware vendor..."
dd if="$EMMC" bs=512 skip="$ENV_SKIP" count=256 2>/dev/null | tr '\0' '\n' > /tmp/env-now.txt
HAS_START_AUTOSCRIPT=0
grep -aqE "^start_autoscript=" /tmp/env-now.txt && HAS_START_AUTOSCRIPT=1

if [[ "$HAS_START_AUTOSCRIPT" == "1" ]]; then
    VARIANTE="A"
    say "Variante detectada: ${G}A${N} (existe start_autoscript)."
    say "  -> alvo: start_emmc_autoscript"
else
    VARIANTE="B"
    say "Variante detectada: ${G}B${N} (bootcmd = run storeboot, sem start_autoscript)."
    say "  -> alvo: o proprio bootcmd"
fi

# =============================================================================
# 1. Confirmacao
# =============================================================================
echo
warn "Isto vai APAGAR o eMMC interno (inclui o Android original)."
say  "eMMC alvo:"
lsblk "$EMMC" 2>/dev/null || true
echo
read -rp "$(echo -e "${Y}Instalar agora? [y/n] ${N}")" ANS
case "$ANS" in y|Y|s|S) say "Confirmado.";; *) say "Cancelado."; exit 0;; esac

# =============================================================================
# 2. Backups (env, factory, bootloader) -> pendrive
# =============================================================================
say "=== 1/6 Backups de seguranca ==="
mkdir -p "$BACKUP_DIR"
dd if="$EMMC" bs=512 skip="$ENV_SKIP" count="$ENV_COUNT" of="$BACKUP_DIR/uboot-env.img" status=none || fail "backup env falhou."
dd if="$EMMC" bs=512 skip="$FACTORY_SKIP" count=16384 of="$BACKUP_DIR/factory-keybox.img" status=none || fail "backup factory falhou."
dd if="$EMMC" bs=512 count=8192 of="$BACKUP_DIR/u-boot.img" status=none || fail "backup bootloader falhou."
( cd "$BACKUP_DIR" && md5sum ./*.img > backups.md5 )
echo "$VARIANTE" > "$BACKUP_DIR/variante.txt"
ok "Backups em $BACKUP_DIR (no pendrive). GUARDE."

# =============================================================================
# 3. Particionar (parted, offsets EXATOS, fim dinamico) + formatar
# =============================================================================
say "=== 2/6 Particionamento ==="
for p in "${EMMC}p1" "${EMMC}p2"; do
    mp=$(findmnt -nro TARGET -S "$p" 2>/dev/null || true)
    [[ -n "$mp" ]] && umount "$mp" 2>/dev/null || true
done

EMMC_NAME=$(basename "$EMMC")
DISK_SECTORS=$(cat "/sys/block/${EMMC_NAME}/size")
P1_END=6041599                       # 2764800 + 3276800 - 1 (fim fixo da /boot)
P2_END=$(( DISK_SECTORS - 34 ))      # rootfs ocupa o resto, com margem
say "eMMC: $DISK_SECTORS setores. rootfs 6057984..$P2_END."

parted --script "$EMMC" mklabel msdos || fail "parted mklabel falhou."
parted --script --align none "$EMMC" \
    unit s \
    mkpart primary fat32 2764800 "$P1_END" \
    mkpart primary ext4  6057984 "$P2_END" \
    set 1 boot on || fail "parted mkpart falhou."
sync; partprobe "$EMMC"; sleep 1
[[ -b "${EMMC}p1" && -b "${EMMC}p2" ]] || fail "Particoes nao apareceram."

GOT_P1=$(cat "/sys/block/${EMMC_NAME}/${EMMC_NAME}p1/start" 2>/dev/null)
GOT_P2=$(cat "/sys/block/${EMMC_NAME}/${EMMC_NAME}p2/start" 2>/dev/null)
say "Offsets: p1=${GOT_P1} p2=${GOT_P2} (esperado 2764800 / 6057984)"
[[ "$GOT_P1" == "2764800" ]] || fail "Offset p1 errado. Abortei."
[[ "$GOT_P2" == "6057984" ]] || fail "Offset p2 errado. Abortei."
ok "Particoes nos offsets corretos."

say "=== 3/6 Formatacao ==="
mkfs.vfat -F 32 -n BOOT "${EMMC}p1" >/dev/null || fail "mkfs.vfat falhou."
mkfs.ext4 -qF -L rootfs "${EMMC}p2" || fail "mkfs.ext4 falhou."
ok "Formatado."

# =============================================================================
# 4. Copiar sistema + fstab
# =============================================================================
say "=== 4/6 Copia do sistema (5-10 min) ==="
mkdir -p /mnt/emmc-boot /mnt/emmc-root
mount "${EMMC}p1" /mnt/emmc-boot || fail "mount p1 falhou."
mount "${EMMC}p2" /mnt/emmc-root || fail "mount p2 falhou."

say "Copiando /boot..."
cp -a /boot/. /mnt/emmc-boot/ || fail "cp /boot falhou."
# nao leva instalador/backups/patch/originais pro eMMC
rm -f /mnt/emmc-boot/instalar.sh /mnt/emmc-boot/verificar.sh /mnt/emmc-boot/emmc_autoscript.src 2>/dev/null || true
rm -f /mnt/emmc-boot/aml_autoscript.devmfc-original /mnt/emmc-boot/bootscript.devmfc-original 2>/dev/null || true
rm -rf /mnt/emmc-boot/amlboot-backups 2>/dev/null || true
sync

say "Copiando rootfs (rsync)..."
rsync -axHAX --info=progress2 \
    --exclude='/dev/*' --exclude='/proc/*' --exclude='/sys/*' \
    --exclude='/tmp/*' --exclude='/run/*' --exclude='/mnt/*' \
    --exclude='/media/*' --exclude='/lost+found' \
    / /mnt/emmc-root/ || fail "rsync falhou."
sync
ok "Sistema copiado."

BOOT_UUID=$(blkid -s UUID -o value "${EMMC}p1")
ROOT_UUID=$(blkid -s UUID -o value "${EMMC}p2")
cat > /mnt/emmc-root/etc/fstab <<EOF
UUID=${ROOT_UUID}  /      ext4  defaults,noatime     0 1
UUID=${BOOT_UUID}  /boot  vfat  defaults,umask=077   0 2
EOF
[[ -f /mnt/emmc-boot/boot.config ]] && sed -i 's/^box=s905x4_generic_gigabit/box=s905x4_generic/' /mnt/emmc-boot/boot.config || true
umount /mnt/emmc-boot /mnt/emmc-root
ok "fstab e boot.config ajustados."

# =============================================================================
# 5. Gravar emmc_autoscript na factory (mmc 1:6)
# =============================================================================
say "=== 5/6 Gravando bootscript na factory ==="
mkdir -p /mnt/factory
mount -t vfat -o "loop,offset=${FACTORY_OFFSET},sizelimit=${FACTORY_SIZE}" "$EMMC" /mnt/factory \
    || fail "mount factory falhou."
cp /tmp/emmc_autoscript /mnt/factory/emmc_autoscript
sync
M1=$(md5sum /tmp/emmc_autoscript | awk '{print $1}')
M2=$(md5sum /mnt/factory/emmc_autoscript | awk '{print $1}')
umount /mnt/factory
[[ "$M1" == "$M2" ]] || fail "Checksum do emmc_autoscript nao bate."
ok "emmc_autoscript gravado e verificado na factory."

# =============================================================================
# 6. Patch no aml_autoscript conforme a variante (o passo sem-UART)
# =============================================================================
say "=== 6/6 Configurando o env (variante $VARIANTE, patch no aml_autoscript) ==="

# monta o bloco de patch conforme a variante
TARGET_LINE='if fatload mmc 1:6 1020000 emmc_autoscript; then autoscr 1020000; fi;'
if [[ "$VARIANTE" == "A" ]]; then
    PATCH_SETENV="setenv start_emmc_autoscript '$TARGET_LINE'"
else
    PATCH_SETENV="setenv bootcmd '$TARGET_LINE run storeboot'"
fi

cat > /tmp/aml-patched.src <<PATCH
echo "=== AmlBoot: gravando env (variante $VARIANTE) ==="
# neutraliza os saveenv condicionais do devmfc (cmd_boot_get_order)
setenv onetime_boot_order
setenv bootfromnand 0
$PATCH_SETENV
saveenv
echo "=== AmlBoot: env gravado ==="
PATCH
cat /tmp/aml.txt >> /tmp/aml-patched.src

mkimage -C none -A arm -T script -d /tmp/aml-patched.src /tmp/aml-patched >/dev/null \
    || fail "Falha recompilando o aml_autoscript."
cp /tmp/aml-patched "$AML"
sync
M3=$(md5sum /tmp/aml-patched | awk '{print $1}')
M4=$(md5sum "$AML" | awk '{print $1}')
[[ "$M3" == "$M4" ]] || fail "Checksum do aml_autoscript nao bate."
ok "aml_autoscript patcheado (variante $VARIANTE)."

# restaura o bootscript original do pendrive (caso um patch antigo tenha mexido)
if [[ -f "$BOOT/bootscript.devmfc-original" ]]; then
    cp "$BOOT/bootscript.devmfc-original" "$BOOT/bootscript"
    sync
    ok "bootscript do pendrive restaurado ao original."
fi

# =============================================================================
# FIM
# =============================================================================
echo
echo "================================================================"
echo -e "   ${G}INSTALACAO CONCLUIDA (variante $VARIANTE)${N}"
echo "================================================================"
echo
say "Agora, a reinicializacao que grava o env (UMA vez pelo pendrive):"
echo "  1. Desligue (tire da tomada)."
echo "  2. Aperte UPDATE e ligue -> boota pelo pendrive DE NOVO."
echo "  3. Deixe o Debian live subir e faca login."
echo "  4. Confira se o env foi gravado:"
echo -e "     ${Y}bash /boot/verificar.sh${N}"
echo "  5. Se der verde: desligue, REMOVA o pendrive, ligue -> eMMC (~5s)."
echo
warn "Se algo der errado: pendrive + UPDATE sempre boota o live."
warn "Restaurar env original:"
warn "  dd if=$BACKUP_DIR/uboot-env.img of=$EMMC bs=512 seek=1875968 conv=fsync"
