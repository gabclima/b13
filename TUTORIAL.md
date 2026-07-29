# Tutorial — Debian autônomo no eMMC da BTV B13 (Amlogic S905X4)

Como instalar Debian 13 direto no eMMC interno de uma BTV B13, com boot
autônomo (~5 s, sem pendrive, sem toothpick), usando um **pendrive
auto-instalador — sem UART, sem soldar nada**.

> **Novo na v2.0:** o método sem-UART. Antes era preciso soldar pinos e usar
> um ESP32 pra acessar o console serial e modificar o u-boot. Agora um script
> faz tudo a partir do próprio Debian live, e a gravação do u-boot acontece
> automaticamente. O método por UART virou apêndice (plano B / diagnóstico).

---

## O que você vai ter no final

- Debian 13 (Trixie) + XFCE bootando do eMMC interno em ~5 segundos
- Sem pendrive plugado, sem apertar UPDATE — liga na tomada e usa
- Ethernet, SSH, HDMI funcionando
- GPU acelerada (depois das otimizações opcionais)

O que **não** funciona (limitação de driver mainline, não do método): WiFi e
Bluetooth (chip Unisoc UWE5621DS) e áudio HDMI. Use cabo de rede e, se precisar,
um dongle WiFi USB.

---

## Hardware necessário

- BTV B13 (Amlogic S905X4)
- Um pendrive (8 GB ou mais)
- Cabo de rede (ethernet) — necessário durante a instalação
- Um palito/toothpick pra apertar o botão UPDATE (dentro do conector AV)
- Um PC com Windows, Linux ou Mac pra gravar o pendrive

**Não precisa** de ESP32, adaptador USB-serial, nem soldar nada. (Isso só é
necessário no plano B via UART, no apêndice.)

---

## Visão geral do processo

1. **Fase 1** — gravar a imagem devmfc Debian num pendrive
2. **Fase 2** — copiar 2 arquivos do AmlBoot pro pendrive
3. **Fase 3** — bootar o Debian live e rodar `instalar.sh`
4. **Fase 4** — reiniciar uma vez pelo pendrive (grava o u-boot) e verificar
5. **Fase 5** — remover o pendrive e bootar do eMMC

As Fases 3-4 são um script cada. O trabalho manual é mínimo.

---

## Fase 0 — Backup do Android original (CRÍTICO)

Antes de tudo, faça um backup completo do firmware Android de fábrica com a
**Amlogic USB Burning Tool** (Windows). Esse é o único seguro contra o pior
caso (um erro na gravação do u-boot que impeça o boot). O procedimento está no
`DIARIO.md`, seção de backup.

> Sem esse backup, um erro grave pode deixar a TV box inutilizável. **Faça.**

---

## Fase 1 — Pendrive Devmfc Debian

### 1.1 Baixar a imagem

Baixe a imagem **Minimal Debian** mais recente do projeto devmfc:
https://github.com/devmfc/debian-on-amlogic/releases

Procure o arquivo `Devmfc_Debian-Trixie_X.XX.XX-meson64_Minimal-XX.XX.XX.img.xz`.
(Testado com a 6.18.40. Versões próximas devem funcionar igual.)

### 1.2 Gravar no pendrive

Use o [Balena Etcher](https://etcher.balena.io/) (Windows/Mac/Linux) ou `dd`:

```bash
# Linux — troque sdX pelo seu pendrive (confira com lsblk!)
xzcat Devmfc_Debian-Trixie_*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

### 1.3 Configurar box.config

Depois de gravar, a partição **BOOT** (FAT32) aparece no seu PC. Abra o
`boot.config` (ou `box-config`) e garanta esta linha, sem comentário:

```
box=s905x4_generic
```

**NUNCA use `box=s905x4_generic_gigabit`** — a B13 é 100 Mbps por hardware, e o
perfil gigabit causa problemas de rede.

### 1.4 Confirme que o live boota (recomendado)

Antes de mexer no AmlBoot, vale um teste "seco": plugue o pendrive na B13,
aperte UPDATE com o palito e ligue. O Debian live deve subir e pedir login
(`root` / `tvbox`). Se subir, o hardware e a imagem estão OK. Desligue e siga.

---

## Fase 2 — Copiar o AmlBoot pro pendrive

Baixe o `amlboot-b13-v2.zip` da [release](https://github.com/gabclima/b13/releases)
e extraia. Copie estes **2 arquivos** para a **raiz da partição BOOT** do
pendrive (a mesma que aparece no seu PC, junto do `vmlinuz`, `boot.config` etc):

- `instalar.sh`
- `emmc_autoscript.src`

(Opcionalmente copie também o `verificar.sh` — o `instalar.sh` também o gera
sozinho no pendrive, então qualquer um serve.)

Ejete o pendrive com segurança.

---

## Fase 3 — Instalar no eMMC

1. Plugue o pendrive na B13, aperte UPDATE e ligue. O Debian live sobe.
2. Faça login: **`root`** / **`tvbox`**
3. Conecte o **cabo de rede** (a instalação baixa algumas ferramentas).
4. Rode:

```bash
bash /boot/instalar.sh
```

O script vai:
- Detectar qual **variante de firmware** a sua B13 tem (veja o quadro abaixo)
- Fazer backup do env, factory e bootloader (pro próprio pendrive)
- Particionar o eMMC com os offsets corretos e formatar
- Copiar o sistema (kernel + rootfs)
- Gravar o `emmc_autoscript` na factory partition
- Preparar o patch do u-boot conforme a variante

Ele pede confirmação (`y`) antes de apagar o eMMC. Ao terminar, dá instruções.

> **As duas variantes de firmware.** Existem (pelo menos) duas versões do u-boot
> vendor da B13, com `bootcmd` diferente. O `instalar.sh` detecta qual é a sua e
> aplica o método certo automaticamente — você não precisa fazer nada. Detalhes
> no `DIARIO.md`.

---

## Fase 4 — Gravar o u-boot e verificar

Esta é a etapa que substitui a UART. A gravação do env do u-boot acontece
**de dentro do próprio u-boot vendor**, disparada por um patch que o
`instalar.sh` colocou no pendrive.

1. Desligue a B13 (tire da tomada).
2. Aperte UPDATE e ligue — **boota pelo pendrive de novo**. Nesse boot, o u-boot
   grava o env automaticamente. (Você não vê mensagem na tela — o texto do
   u-boot só sai pela UART. Isso é normal.)
3. Deixe o Debian live subir e faça login.
4. **Antes de remover o pendrive**, confirme que o env foi gravado:

```bash
bash /boot/verificar.sh
```

- Se aparecer **`[ OK ] ... aponta para a factory`** (verde): deu certo, siga.
- Se aparecer vermelho ou amarelo: **não remova o pendrive** e veja o
  Troubleshooting.

---

## Fase 5 — Boot autônomo do eMMC

1. Desligue.
2. **Remova o pendrive.**
3. Ligue.

O Debian deve bootar do eMMC em ~5 segundos, direto no login, sem pendrive e sem
toothpick. Confirme:

```bash
uname -a                # kernel meson64
systemd-analyze         # tempo de boot
findmnt /               # deve ser /dev/mmcblk1p2 (eMMC), não sda2 (pendrive)
```

Pronto — Debian autônomo no eMMC. As otimizações abaixo são opcionais.

---

## Otimizações XFCE (opcionais mas recomendadas)

Por padrão o XFCE fica engasgado nessa BTV. Esses ajustes resolvem ~90% do lag.

### Governor da GPU em performance

Copie o `gpu-performance.service` (no zip) para
`/etc/systemd/system/gpu-performance.service`. Depois:
```bash
systemctl daemon-reload
systemctl enable --now gpu-performance.service
cat /sys/class/devfreq/fe400000.gpu/cur_freq   # esperado: 846000000
```

A Mali-G31 vai pular de 285 MHz pra 846 MHz (3x). Sem isso o XFCE engasga porque
o devfreq governor padrão (`simple_ondemand`) não rampa o clock pra cargas leves
de UI.

### Xorg com DRI3 + PageFlip + glamor

Copie o `20-meson.conf` (no zip) para `/etc/X11/xorg.conf.d/20-meson.conf`.
Reinicie:
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

### Bônus: dissipação térmica

O EMI shield de metal sobre o SoC costuma ter folga (é blindagem, não
dissipação). Apertá-lo contra o SoC já baixa 5-7 °C; um thermal pad fino
(1–1.5 mm) entre SoC e shield é a solução permanente pra uso 24/7.

---

## Casos de uso reais da B13

**✅ Funciona bem como servidor:**
Pi-hole / AdGuard Home, Home Assistant, MQTT (Mosquitto), SSH bastion,
Docker leve (1-2 containers), node K3s de estudo, cron/backups/monitoramento.

**⚠️ Com limitações:**
Servidor de arquivos LAN pequena (rede 100M = 12 MB/s teto), WireGuard
(~30-50 Mbps, CPU é gargalo na crypto).

**❌ Não serve pra:**
Desktop com navegador moderno, mediabox 4K (sem decode HW no Mesa mainline),
transcoding (Jellyfin/Plex), workstation Linux normal.

---

## Troubleshooting

### `verificar.sh` deu vermelho ("bootcmd ficou com o multiboot do devmfc")

O env foi gravado poluído. Restaure o env original e rode o `instalar.sh` de
novo (ele foi corrigido pra gravar antes da poluição):
```bash
dd if=/boot/amlboot-backups/uboot-env.img of=/dev/mmcblk1 bs=512 seek=1875968 conv=fsync
sync
```

### `verificar.sh` deu amarelo ("o patch não rodou")

O u-boot não executou o `aml_autoscript` patcheado. Confirme que você reiniciou
**pelo pendrive** (UPDATE + ligar), não direto do eMMC. Repita a Fase 4.

### Boot do eMMC fica preto / trava na logo

Plugue o pendrive + UPDATE (sempre boota o live) e rode `verificar.sh`. Se o
`bootcmd`/`start_emmc_autoscript` estiver certo mas não bootar, o problema é o
`fatload mmc 1:6` não achar a factory ou o bootscript. Confira:
```bash
# emmc_autoscript existe na factory?
mkdir -p /mnt/fac && mount -t vfat -o loop,offset=1029701632,sizelimit=8388608 /dev/mmcblk1 /mnt/fac
ls -la /mnt/fac/ ; umount /mnt/fac
# kernel e bootscript na /boot do eMMC?
mkdir -p /mnt/chk && mount /dev/mmcblk1p1 /mnt/chk
ls /mnt/chk/vmlinuz-* /mnt/chk/bootscript ; umount /mnt/chk
```
Se algo faltar, rode o `instalar.sh` de novo. Se tudo estiver lá, o diagnóstico
fino só é possível pela UART (veja o apêndice).

### Recuperação total (voltar ao Android)

Se precisar voltar tudo ao estado de fábrica, reflashe o backup do Android
original com a Amlogic USB Burning Tool (Windows). É por isso que a Fase 0 é
obrigatória.

### WiFi / Bluetooth / áudio HDMI não funcionam

Limitação de driver mainline (chip Unisoc UWE5621DS / meson-aiu parcial), não do
método. Use cabo de rede e, se precisar de WiFi, um dongle USB com chip Realtek.

---

## Apêndice — Método por UART (plano B / diagnóstico)

O método sem-UART cobre os dois firmwares conhecidos. Mas se você tiver uma
variante nova, ou quiser **ver** o que o u-boot faz (as mensagens de boot só
saem pela serial), o acesso UART é a ferramenta de diagnóstico definitiva.

Resumo (detalhes completos no `DIARIO.md`):

1. Solde pinos nos 4 pads UART (GND/TX/RX/3V3) — do lado das USBs.
2. Use um ESP32 como adaptador USB-serial (sketch `esp32-uart-bridge.ino` no
   zip). Ligação: ESP32 GND↔BTV GND, GPIO16↔BTV TX, GPIO17↔BTV RX. 115200 baud.
3. Ligue a B13, interrompa o autoboot pra cair no prompt (`sc2_ah212#`).
4. Descubra a variante:
   ```
   printenv bootcmd
   printenv start_autoscript
   ```
   - Se `start_autoscript` existir → grave `start_emmc_autoscript`:
     ```
     setenv start_emmc_autoscript 'if fatload mmc 1:6 1020000 emmc_autoscript; then autoscr 1020000; fi;'
     saveenv
     ```
   - Se só houver `bootcmd=run storeboot` → grave o `bootcmd`:
     ```
     setenv bootcmd 'if fatload mmc 1:6 1020000 emmc_autoscript; then autoscr 1020000; fi; run storeboot'
     saveenv
     ```
5. Desligue, remova o pendrive, ligue.

---

## Anexos (no `amlboot-b13-v2.zip`)

- `instalar.sh` — instalador universal (detecta variante, sem UART)
- `verificar.sh` — confere o env gravado antes de remover o pendrive
- `emmc_autoscript.src` — script u-boot do boot do eMMC (fonte)
- `gpu-performance.service` — governor da GPU em performance
- `20-meson.conf` — config do Xorg
- `esp32-uart-bridge.ino` — sketch do ESP32 (só pro plano B via UART)

---

## Créditos

Procedimento desenvolvido por **Gabriel Lima** com assistência de Claude
(Anthropic). Baseado no [devmfc/debian-on-amlogic](https://github.com/devmfc/debian-on-amlogic).
