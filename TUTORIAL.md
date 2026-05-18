# Tutorial — Debian autônomo no eMMC da BTV B13 (Amlogic S905X4)

Procedimento passo a passo pra fazer uma TV Box BTV B13 bootar **Debian 13 + XFCE direto do eMMC interno** — sem pendrive permanente, sem toothpick toda vez. Funciona a frio: liga na tomada → Debian em ~30 segundos.

---

## O que você vai ter no final

- Debian 13 (Trixie) com kernel mainline 6.18 rodando do eMMC
- XFCE com aceleração GPU (Mali-G31 via Panfrost)
- SSH, ethernet, áudio HDMI funcionando
- Boot autônomo: ligar e pronto
- WiFi e Bluetooth **não funcionam** (chip MT7668 sem driver mainline + DTB genérico) — usar dongle USB

---

## Hardware necessário

| Item | Notas |
|---|---|
| TV Box **BTV B13** com Amlogic **S905X4 (SC2)** | Confirme abrindo o caso ou via AIDA64 no Android original |
| Pendrive 4-8GB (qualquer um) | Pra gravação inicial da imagem devmfc |
| **ESP32 + jumpers** (~R$30) | Adaptador UART pra acessar o u-boot vendor |
| Computador com Linux ou WSL | Pra gravar imagem, compilar scripts, SSH |
| Cabo ethernet | WiFi não funciona, ethernet é obrigatório |
| Toothpick / alfinete | Pra apertar o botão recovery escondido na porta AV |
| Teclado USB | Pro Debian inicial (Compx ou similar, NÃO mouse gamer 8K) |
| Monitor + cabo HDMI | Pra ver o que tá fazendo |

---

## Fase 0 — Backup do Android original

**FAÇA ESTE PASSO.** Sem backup, se algo der errado, a B13 vira tijolo. Roda no Android original via app, ou usa Amlogic USB Burning Tool no Windows pra fazer dump completo do eMMC. Guarda o `.img` num lugar seguro.

> Tutorial detalhado de backup: <https://github.com/educabox/educabox/blob/main/boxes/btv11.md>

---

## Fase 1 — Pendrive Devmfc Debian

### 1.1 Baixar a imagem

Repositório: <https://github.com/devmfc/debian-on-amlogic>

Procure a release mais recente, baixe a imagem genérica para Amlogic S905X4. Algo tipo:
`Debian_trixie_amlogic-s905x4_xfce_X.X.X.img.xz`

### 1.2 Gravar no pendrive

No PC com Linux:
```bash
xz -d Debian_trixie_amlogic-s905x4_xfce_X.X.X.img.xz
sudo dd if=Debian_trixie_amlogic-s905x4_xfce_X.X.X.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```
Substitua `/dev/sdX` pelo seu pendrive (confirma com `lsblk` antes — gravar no disco errado destrói dados).

Ou usa Balena Etcher se preferir GUI.

### 1.3 Configurar boot.config

Monte a partição BOOT do pendrive (FAT32), edite o `boot.config` e **descomente** a linha do S905X4:

```
box=s905x4_generic_gigabit
```

(Use `s905x4_generic` se sua B13 for de 100 Mbps em vez de gigabit — vê no conector ethernet.)

### 1.4 Boot pelo pendrive (toothpick)

1. Desligue a B13 da tomada
2. Plugue o pendrive **em uma porta USB 2.0** (não USB 3.0)
3. Plugue teclado e monitor HDMI
4. Pegue o toothpick e enfie no buraquinho do botão "RECOVERY/UPDATE" — fica dentro da porta AV (RCA amarelo)
5. **Segure o botão pressionado** e ligue a B13 na tomada
6. Continue segurando por 7-10 segundos depois de ligar
7. Solte. Debian deve começar a bootar do pendrive

Login default: `root` / `tvbox`

Confirma que tá rodando:
```bash
uname -r              # 6.18.x-meson64
cat /proc/device-tree/model    # Amlogic SC2 AH212 Development Board
df /                  # rootfs em /dev/sda2
ip a                  # eth0 deve pegar IP
```

---

## Fase 2 — Preparar eMMC do zero

> ⚠️ **Esta fase apaga o Android original do eMMC.** Tenha certeza que tem backup.

### 2.1 Particionar o eMMC

```bash
# Confirma que /dev/mmcblk1 é o eMMC interno (não confunda com mmcblk0 = SD)
lsblk
fdisk -l /dev/mmcblk1

# Cria nova tabela MBR com 2 partições alinhadas com o layout vendor AML:
sfdisk /dev/mmcblk1 << 'EOF'
label: dos
device: /dev/mmcblk1
unit: sectors

/dev/mmcblk1p1 : start=2764800, size=3276800, type=c, bootable
/dev/mmcblk1p2 : start=6057984, size=24727552, type=83
EOF

sync; partprobe /dev/mmcblk1; ls /dev/mmcblk1p*
```

A mágica está nos offsets: `2764800` e `6057984` batem com o início das partições vendor `super` e `userdata`. Isso permite que o u-boot vendor leia a FAT32 via `mmc 1:15` hex (= partição 21 = "super") sem precisar entender MBR.

### 2.2 Formatar

```bash
mkfs.vfat -F 32 -n BOOT /dev/mmcblk1p1
mkfs.ext4 -L rootfs /dev/mmcblk1p2
```

### 2.3 Copiar /boot e rootfs

```bash
mkdir -p /mnt/emmc-boot /mnt/emmc-root
mount /dev/mmcblk1p1 /mnt/emmc-boot
mount /dev/mmcblk1p2 /mnt/emmc-root

# Copia /boot do pendrive (atualmente em /boot, vindo do sda1)
cp -av /boot/* /mnt/emmc-boot/
sync

# Copia rootfs (exceto pontos de montagem e dirs especiais)
rsync -axHAX --info=progress2 --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found} / /mnt/emmc-root/
sync
```

### 2.4 Ajustar /etc/fstab no eMMC

```bash
BOOT_UUID=$(blkid -s UUID -o value /dev/mmcblk1p1)
ROOT_UUID=$(blkid -s UUID -o value /dev/mmcblk1p2)

cat > /mnt/emmc-root/etc/fstab << EOF
UUID=$ROOT_UUID  /      ext4  defaults,noatime  0 1
UUID=$BOOT_UUID  /boot  vfat  defaults,umask=077  0 2
EOF

cat /mnt/emmc-root/etc/fstab
```

### 2.5 Ajustar boot.config da partição /boot do eMMC

Edite `/mnt/emmc-boot/boot.config` e garante que aponta pro eMMC:
```
box=s905x4_generic_gigabit
```
(Mesma config do pendrive — `box=` é o mesmo nome.)

---

## Fase 3 — Gravar emmc_autoscript na factory partition

Esta é a parte que faz o vendor u-boot bootar do eMMC sozinho.

### 3.1 Compilar o emmc_autoscript_full

Pegue o source `emmc_autoscript_full.src` (anexo deste tutorial) e:

```bash
apt install -y u-boot-tools
cd /root
# (salvar o emmc_autoscript_full.src aqui antes)
mkimage -C none -A arm -T script -d emmc_autoscript_full.src emmc_autoscript_full
ls -la emmc_autoscript_full   # ~900 bytes
mkimage -l emmc_autoscript_full
```

### 3.2 Gravar na factory partition (mmc 1:6)

```bash
mkdir -p /mnt/factory
mount -t vfat -o loop,offset=1029701632,sizelimit=8388608 /dev/mmcblk1 /mnt/factory
ls /mnt/factory/

cp emmc_autoscript_full /mnt/factory/emmc_autoscript
sync

# Verifica
ls -la /mnt/factory/emmc_autoscript
md5sum emmc_autoscript_full /mnt/factory/emmc_autoscript    # devem bater
umount /mnt/factory
sync
```

> Os números mágicos: `1029701632` é o offset em bytes da partição "factory" (mmc 1:6 no schema AML, sector 2011136 × 512). `8388608` é o tamanho de 8MB. A partição é FAT12 com label "KEYBOX PART", originalmente destinada a chaves DRM do Android — a gente sequestra ela.

---

## Fase 4 — Modificar env do u-boot via UART

Esta é a etapa que faz `start_emmc_autoscript` apontar pra factory partition e persiste a config.

### 4.1 Setup do ESP32 como adaptador UART

Pegue o sketch `esp32-uart-bridge.ino` (anexo). Upload no ESP32 via Arduino IDE.

Wiring:
```
ESP32 GND     ─── BTV GND
ESP32 GPIO16  ─── BTV TX    (pinos UART na placa, geralmente labelados SW TX RX GND)
ESP32 GPIO17  ─── BTV RX
```

**Não ligue VCC entre ESP32 e BTV.** Alimentação separada.

### 4.2 Conectar e ligar

1. Plugue ESP32 no PC via USB
2. Abra Serial Monitor a **115200 baud**
3. Ligue a B13 — vai aparecer o log de boot do u-boot vendor
4. Quando aparecer `Hit any key to stop autoboot:`, digite qualquer tecla **rapidamente** (a janela é de milissegundos — se a janela for muito curta, use a versão Auto-Intercept v2 do sketch comentada no .ino)
5. Vai cair no prompt `sc2_ah212#`

### 4.3 Comandos no prompt u-boot

Cole **um comando por linha** (não tudo de uma vez):

```
setenv start_emmc_autoscript 'if fatload mmc 1:6 1020000 emmc_autoscript; then autoscr 1020000; fi;'
```

Confere:
```
printenv start_emmc_autoscript
```

Esperado: `start_emmc_autoscript=if fatload mmc 1:6 1020000 emmc_autoscript; then autoscr 1020000; fi;`

Testa rodando manualmente:
```
run start_emmc_autoscript
```

Se aparecer `bootscript carregado do eMMC (mmc 1:15)!` seguido de boot do kernel → funcionou! Espera o Debian subir, faz login, valida.

Se funcionou, volta no u-boot (`reset`, intercept de novo, ou roda o comando direto sem testar — você pode pular `run` se confiar) e **persiste**:

```
setenv start_emmc_autoscript 'if fatload mmc 1:6 1020000 emmc_autoscript; then autoscr 1020000; fi;'
saveenv
```

Esperado: `Saving Environment to MMC... Writing to MMC(0)... OK`

---

## Fase 5 — Teste de boot autônomo

1. **Desconecte tudo**: pendrive USB, ESP32, teclado (se quiser)
2. Tira o cabo de força da B13
3. Espera 5 segundos
4. Liga de novo — **sem toothpick, sem nada**

Deve bootar Debian em ~30s. Login via SSH funcionando, XFCE no monitor.

Se não bootar: plugga o pendrive de volta + toothpick. Sistema do pendrive vai rodar. Aí investiga o erro (provavelmente `mmc 1:6` ou env não persistiu).

---

## Otimizações XFCE (opcionais mas recomendadas)

Por padrão o XFCE fica engasgado nessa BTV. Esses ajustes resolvem ~90% do lag.

### Governor da GPU em performance

Cria `/etc/systemd/system/gpu-performance.service` com o conteúdo do anexo. Depois:
```bash
systemctl daemon-reload
systemctl enable --now gpu-performance.service
cat /sys/class/devfreq/fe400000.gpu/cur_freq   # esperado: 846000000
```

A Mali-G31 vai pular de 285 MHz pra 846 MHz (3x). Sem isso, o XFCE fica engasgado porque o devfreq governor padrão (`simple_ondemand`) não rampa o clock pra cargas leves de UI.

### Xorg com DRI3 + PageFlip + glamor

Cria `/etc/X11/xorg.conf.d/20-meson.conf` com o conteúdo do anexo. Reinicia:
```bash
systemctl restart lightdm
```

### Compositor XFWM4 com vsync

Como **usuário comum** (não root) na sessão XFCE:
```bash
xfconf-query -c xfwm4 -p /general/use_compositing -s true
xfconf-query -c xfwm4 -p /general/sync_to_vblank -n -t bool -s true
xfconf-query -c xfwm4 -p /general/unredirect_overlays -s true
```

(`-n -t bool` é necessário em `sync_to_vblank` porque a propriedade pode não existir ainda.)

---

## Troubleshooting

### Boot autônomo não funciona, fica preto

Reverter via toothpick + pendrive antigo, depois:
```bash
# Verifica que o emmc_autoscript existe e tá íntegro
mount -t vfat -o loop,offset=1029701632,sizelimit=8388608 /dev/mmcblk1 /mnt/factory
ls -la /mnt/factory/emmc_autoscript
mkimage -l /mnt/factory/emmc_autoscript
umount /mnt/factory

# Confirma via UART que o env persistiu
# (boot, intercept, printenv start_emmc_autoscript)
```

### "Tearing" leve ao arrastar janelas no XFCE

Conhecido. A combinação Mali-G31 + meson-drm + glamor não tem page-flip atômico perfeito. Tearing leve é o estado da arte hoje. Pra eliminar 100% precisaria patchear DTB ou esperar driver melhor.

### XFCE engasgando depois de tudo configurado

Verifica:
1. GPU governor: `cat /sys/class/devfreq/fe400000.gpu/governor` → deve ser `performance`
2. Renderer: `glxinfo | grep Renderer` → deve ser `Mali-G31 (Panfrost)`
3. **Não usa mouse gamer 8K** — mouses de polling acima de 1000 Hz saturam o Xorg nessa CPU
4. Xorg CPU: `ps aux | grep Xorg` → idle ~10-15%, em uso ~30%

### WiFi não funciona

O chip wifi é MediaTek MT7668 SDIO. Driver out-of-tree (`wlan_mt76x8_sdio.ko`) carrega mas o chip não responde com ID válido — falta power-on no DTB genérico. **Solução pragmática:** dongle USB WiFi (Realtek RTL8188FU, MT7601U, ~R$20). Solução completa: patchear DTB com nó wifi específico do BTV B13.

---

## Anexos

Arquivos disponíveis junto deste tutorial:

- `bootscript-amlboot.src` — bootscript patched (alternativa via pendrive ao invés de UART, projeto futuro)
- `emmc_autoscript_full.src` — script u-boot do boot autônomo do eMMC
- `gpu-performance.service` — systemd unit pra GPU em performance
- `20-meson.conf` — config do Xorg
- `esp32-uart-bridge.ino` — sketch do ESP32 como adaptador UART

---

## Créditos

Procedimento desenvolvido por Gabriel Lima com assistência de Claude (Anthropic) em sessão única em 15/05/2026. Baseado no trabalho do projeto [devmfc/debian-on-amlogic](https://github.com/devmfc/debian-on-amlogic) como ponto de partida.
