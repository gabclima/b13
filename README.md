<h1 align="center">AmlBoot B13</h1>

<p align="center">
  <img src="imagens/topo.png" width="320" alt="BTV B13">
</p>

<p align="center">
  <b>Debian 13 autônomo no eMMC interno de uma BTV B13 (Amlogic S905X4).</b>
</p>

Engenharia reversa do bootloader vendor de uma TV Box BTV B13 pra rodar Debian
13 + XFCE direto do eMMC interno — sem pendrive, sem toothpick, ligar e usar.

**v2.0 — agora sem UART.** Um pendrive auto-instalador faz tudo a partir do
Debian live; a gravação do u-boot acontece automaticamente. Não precisa mais
soldar pinos nem usar ESP32.

## Conteúdo

| Arquivo | Pra quê |
|---|---|
| **[`TUTORIAL.md`](TUTORIAL.md)** | Procedimento passo a passo (método sem-UART) |
| **[`DIARIO.md`](DIARIO.md)** | Diário técnico completo: processo, descobertas, benchmarks, lições |
| **[Releases](https://github.com/gabclima/b13/releases)** | `amlboot-b13-v2.zip` — o instalador + scripts |
| `scripts/` | Arquivos auxiliares (configs, scripts u-boot, sketch ESP32) |
| `imagens/` | Fotos do hardware (carcaça, placa) e screenshots AIDA64 |

## Começar rápido

1. Grave a imagem devmfc Debian num pendrive (ver `TUTORIAL.md` Fase 1)
2. Copie `instalar.sh` + `emmc_autoscript.src` (do zip da release) pra raiz da BOOT
3. Boote o live na B13 (`root`/`tvbox`), com cabo de rede, e rode:
   `bash /boot/instalar.sh`
4. Reinicie uma vez pelo pendrive, rode `bash /boot/verificar.sh`
5. Remova o pendrive e ligue → Debian do eMMC em ~5 s

## Quem deve usar isso

- **Tem uma BTV B13** (S905X4) e quer rodar Linux nela → `TUTORIAL.md`
- **Quer entender como foi feito** → `DIARIO.md`
- **Quer adaptar pra outro modelo Amlogic** → ambos

## Status

- ✅ Boot autônomo do eMMC funcionando (~5 segundos)
- ✅ **Instalador sem UART** (v2.0) — pendrive auto-instalador, sem soldar nada
- ✅ **Detecção automática de variante** — funciona nos dois firmwares vendor conhecidos
- ✅ XFCE com aceleração GPU otimizado
- ✅ Ethernet, SSH, HDMI
- ✅ Benchmarks: térmica boa (51-58 °C sob stress), rede satura 100M, eMMC midrange
- ❌ WiFi (chip Unisoc UWE5621DS, driver mainline ausente)
- ❌ Bluetooth (mesmo chip — controle remoto da B13 é BT, não funciona)
- ❌ Áudio HDMI (driver meson-aiu parcial)

## O hardware

<table>
<tr>
<td align="center"><img src="imagens/topo.png" width="350" alt="Carcaça topo"></td>
<td align="center"><img src="imagens/placafundo.png" width="350" alt="Placa verso"></td>
</tr>
<tr>
<td align="center"><sub>Carcaça (topo)</sub></td>
<td align="center"><sub>Placa (verso)</sub></td>
</tr>
<tr>
<td align="center"><img src="imagens/fundo.png" width="350" alt="Carcaça verso"></td>
<td align="center"><img src="imagens/placafrente.png" width="350" alt="Placa frente"></td>
</tr>
<tr>
<td align="center"><sub>Carcaça (verso — RESET e UPDATE)</sub></td>
<td align="center"><sub>Placa (frente — SoC, RAM, eMMC)</sub></td>
</tr>
</table>

### Identificação via AIDA64 (no Android original)

<table>
<tr>
<td align="center" width="50%"><img src="imagens/sistemab13.png" width="400" alt="AIDA64 Sistema"></td>
<td align="center" width="50%"><img src="imagens/processadorb13.png" width="400" alt="AIDA64 Processador"></td>
</tr>
<tr>
<td align="center"><sub>Sistema</sub></td>
<td align="center"><sub>Processador (S905X4, 4× A55)</sub></td>
</tr>
<tr>
<td align="center"><img src="imagens/telab13.png" width="400" alt="AIDA64 GPU"></td>
<td align="center"><img src="imagens/dispositivosb13.png" width="400" alt="AIDA64 USB"></td>
</tr>
<tr>
<td align="center"><sub>GPU (Mali-G31)</sub></td>
<td align="center"><sub>Dispositivos USB</sub></td>
</tr>
</table>

## Hardware testado

|  |  |
|---|---|
| TV Box | BTV B13 ("OTT BOX" / "OTT TV BOX") |
| Versão da placa | B13_V1.0_20220406 |
| SoC | Amlogic S905X4 (SC2, codename `ohm`, board `sc2_ah212`) |
| CPU | 4× Cortex-A55 @ até 2.0 GHz |
| GPU | Mali-G31 MP2 (Panfrost) |
| RAM | 2 GB DDR4 |
| Storage | 16 GB eMMC Samsung KLMAG1JETD (tamanho exato varia entre unidades) |
| Ethernet | 100 Mbps (hardware limit) |
| WiFi/BT | Unisoc UWE5621DS (não funciona no Debian mainline) |

## As duas variantes de firmware

Ao testar em unidades diferentes, descobrimos que **existe mais de uma versão do
u-boot vendor da B13**, com `bootcmd` diferente:

| | Variante A | Variante B |
|---|---|---|
| `bootcmd` | `run start_autoscript; run storeboot` | `run storeboot` |
| Alvo pra boot do eMMC | `start_emmc_autoscript` | o próprio `bootcmd` |

O `instalar.sh` **detecta a variante automaticamente** e aplica o método certo.
Quem tinha só a variante A documentada e usasse o método antigo numa placa
variante B travaria na logo — por isso a detecção é importante. Detalhes no
`DIARIO.md`.

## Casos de uso

- ✅ **Servidor ARM low-power:** Pi-hole, Home Assistant, MQTT, SSH bastion, automação, K3s node
- 🟡 **Desktop leve:** terminal, editor de texto, configuração
- ❌ **Desktop pesado:** navegador moderno, vídeo, transcoding — CPU/decode insuficientes

## Créditos

Procedimento desenvolvido por **Gabriel Lima** com assistência de Claude
(Anthropic). Baseado no excelente trabalho do
[devmfc/debian-on-amlogic](https://github.com/devmfc/debian-on-amlogic) como
ponto de partida.

## Licença

Documentação e scripts neste repositório: MIT.
Arquivos derivados de outros projetos (devmfc bootscripts) mantêm a licença
original (GPL-2.0+).
