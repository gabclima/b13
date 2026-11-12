# Extras: Ethernet, Bluetooth interno e áudio em tempo real na B13

Correções testadas numa BTV B13 (variante B, `bootcmd=run storeboot`) com o Debian do devmfc
6.18.40 instalado no eMMC por este projeto. Nada aqui grava o bootloader.

A pista que resolveu quase tudo: **comparar o DTB do Android com o DTB genérico**. O DTB do
Android fica no eMMC (partição `_aml_dtb`, ~40 MiB do início; procure a assinatura FDT `d00dfeed`
no backup) e vira texto com `dtc -I dtb -O dts`.

## 0. Backup completo sem Windows

O Debian "live" do pendrive não toca no eMMC, então dá para copiar tudo por SSH antes de rodar o
`instalar.sh` (de outro computador, com a B13 ligada pelo pendrive):

```sh
ssh root@<ip> 'dd if=/dev/mmcblk1boot0 bs=1M' > mmcblk1boot0.img     # bootloader (4 MiB)
ssh root@<ip> 'dd if=/dev/mmcblk1boot1 bs=1M' > mmcblk1boot1.img
ssh root@<ip> 'dd if=/dev/mmcblk1 bs=4M | tee >(sha256sum > /tmp/emmc.sha256) | gzip -1' > b13-emmc.img.gz
ssh root@<ip> cat /tmp/emmc.sha256 ; gzip -dc b13-emmc.img.gz | sha256sum   # devem bater
```

Restaurar: bootar o pendrive e `gzip -dc b13-emmc.img.gz | ssh root@<ip> 'dd of=/dev/mmcblk1 bs=4M conv=fsync'`.

## 1. Ethernet perdendo 10–50% dos pacotes recebidos — `ethernet/`

Sintoma: link 100 Mb/s sobe, envio funciona (dá até para fazer o backup acima), mas a recepção
perde pacotes sem nenhum erro nos contadores. Não é cabo, porta, velocidade, EEE nem MAC.

Causa: o DTB genérico deixa o registrador `PRG_ETH0` (0xfe024000) em `0x1e04`. O DTB do Android
usa `mc_val = <0x4be0c>`, que liga o ajuste de tempo da recepção RMII (`ADJ_ENABLE`, bit 13, e
`ADJ_DELAY = 9`). Com `0x4be0c`: 0% de perda.

1. Em `/boot/boot.config`, antes da linha final de aviso: `bootargs14=iomem=relaxed`
   (permite escrever o registrador; o script de boot do devmfc concatena as linhas `bootargsN=`).
2. `gcc -O2 -static -o /usr/local/sbin/regs ethernet/regs.c`
3. `cp ethernet/b13-tune.service /etc/systemd/system/ && systemctl enable --now b13-tune`

## 2. Bluetooth interno (UWE5621DS) sem dongle — `bluetooth-interno/`

O chip aparece no SDIO (`mmc2: new UHS-I speed SDR104 SDIO card`) e o DTB genérico já tem a
sequência de energia e o clock de 32,768 kHz. Faltavam: driver, firmware, SDIO mais lento,
a inicialização do fabricante e contornar um bug do firmware.

1. **Firmware** (do seu próprio backup do Android; não é redistribuído aqui). Extraia a
   partição `super` do backup (tabela `MPT` em 36 MiB; `super` começa em 1350 MiB na minha
   unidade), separe a `vendor` com `lpextract.py` e copie dela:
   - `wcnmodem.bin`: `python3 extrair-firmware.py vendor/lib/modules/uwe5621_bsp_sdio.ko wcnmodem.bin`
     (vem embutido no módulo; o meu é `MARLIN3E_20A_W22.10.2`)
   - `vendor/etc/bt_configure_pskey.ini` e `vendor/etc/bt_configure_rf.ini`

   Coloque `wcnmodem.bin` em `/lib/firmware/` e gere os blocos de configuração:
   `python3 unisoc_ini2bin.py bt_configure_pskey.ini pskey.bin` (160 bytes) e
   `python3 unisoc_ini2bin.py bt_configure_rf.ini rf.bin` (252 bytes).
2. **SDIO a 150 MHz** (`sdio-150mhz.sh`, depois reiniciar): com os 200 MHz do DTB genérico o
   download do firmware falha com erro CRC (`-84`). O Android usa 150 MHz.
3. **Driver**: `bash compilar-modulos.sh linux-headers-<versão>-meson64_*_arm64.deb` (o pacote de
   headers está nas releases do devmfc). Gera `uwe5621_bsp_sdio.ko` e `sprdbt_tty.ko`.
4. **Ferramentas**: `gcc -O2 -static -o unisoc-btinit unisoc-btinit.c` e o mesmo para
   `unisoc-hciproxy.c`.
5. **Instalar**: copie os `.ko`, `pskey.bin`, `rf.bin`, `unisoc-btinit`, `unisoc-hciproxy` e
   `b13-bt-up.sh` para `/usr/local/lib/b13-bt/`, e `b13-bt.service` para `/etc/systemd/system/`.
   `systemctl enable --now b13-bt`.

O que o `b13-bt-up.sh` faz, em ordem:
- carrega os módulos (o `sprdbt_tty` compilado com `OTT_UWE` cria `/dev/ttyBT0` sem nó no DTB);
- desbloqueia o rfkill `bluetooth`, que liga o chip e envia o firmware;
- `unisoc-btinit`: os comandos HCI do fabricante que o `libbt-vendor_uwe.so` do Android envia
  (`0xFCA0` pskey, `0xFCA2` RF, `0xFCA1 00 00 01` habilita) — opcodes tirados da desmontagem;
- `unisoc-hciproxy`: o firmware anuncia "Read Default Link Policy" mas responde com erro `0x12`,
  e o kernel desiste do controlador. O proxy repassa tudo e só apaga esse bit da lista de
  comandos suportados;
- `btattach` entrega o proxy ao kernel como H:4.

Resultado: `hci0` com BLE funcionando (testado com MIDI por Bluetooth de um iPhone, pareando e
reconectando sozinho após reiniciar). Use `ControllerMode = le` em `/etc/bluetooth/main.conf` se
só precisar de BLE.

## 3. Áudio em tempo real

O kernel do devmfc tem `CONFIG_RT_GROUP_SCHED=y`: sob o systemd nenhum cgroup tem cota de tempo
real, então `SCHED_FIFO` é recusado (o áudio estala sem parar). Adicione
`bootargs15=rt_group_sched=0` ao `/boot/boot.config`. Todas as interrupções caem na CPU0, então
fixe o processo de áudio em outra (`CPUAffinity=3` no serviço).
