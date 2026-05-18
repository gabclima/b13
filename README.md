# AmlBoot B13

> Debian 13 autônomo no eMMC interno de uma BTV B13 (Amlogic S905X4).

Engenharia reversa do bootloader vendor de uma TV Box BTV B13 pra rodar Debian 13 + XFCE direto do eMMC interno — sem pendrive, sem toothpick, ligar e usar.

## Conteúdo

| Arquivo | Pra quê |
|---|---|
| **[`TUTORIAL.md`](TUTORIAL.md)** | Procedimento passo a passo replicável em outra B13 |
| **[`DIARIO.md`](DIARIO.md)** | Diário técnico completo do processo, descobertas, benchmarks e lições |
| `scripts/` | Arquivos auxiliares (configs, scripts u-boot, sketch ESP32) |

## Quem deve usar isso

- **Tem uma BTV B13** (S905X4) e quer rodar Linux nela → ver `TUTORIAL.md`
- **Quer entender como foi feito** → ver `DIARIO.md`
- **Quer adaptar pra outro modelo de TV box Amlogic** → ambos

## Status

- ✅ Boot autônomo do eMMC funcionando (~5 segundos)
- ✅ XFCE com aceleração GPU otimizado
- ✅ Ethernet, SSH, HDMI
- ✅ Benchmarks confirmam: térmica boa (51-58°C sob stress), rede satura 100M, eMMC midrange
- ❌ WiFi (chip Unisoc UWE5621DS, driver mainline ausente)
- ❌ Bluetooth (mesmo chip, mesma situação — controle remoto da B13 é BT, não funciona)
- ❌ Áudio HDMI (driver meson-aiu parcial)
- 🚧 Versão 2: pendrive auto-installer (sem UART) — em desenvolvimento

## Hardware testado

| | |
|---|---|
| TV Box | BTV B13 ("OTT BOX") |
| Versão da placa | B13_V1.0_20220406 |
| SoC | Amlogic S905X4 (SC2, codename `ohm`) |
| CPU | 4× Cortex-A55 @ até 2.0 GHz |
| GPU | Mali-G31 MP2 (Panfrost) |
| RAM | 2 GB DDR4 |
| Storage | 16 GB eMMC Samsung KLMAG1JETD |
| Ethernet | 100 Mbps (hardware limit) |
| WiFi/BT | Unisoc UWE5621DS (não funciona no Debian mainline) |

## Casos de uso

✅ **Servidor ARM low-power:** Pi-hole, Home Assistant, MQTT, SSH bastion, automação, K3s node
🟡 **Desktop leve:** terminal, editor de texto, configuração
❌ **Desktop pesado:** navegador moderno, vídeo, transcoding — CPU/decode insuficientes

## Créditos

Procedimento desenvolvido por **Gabriel Lima** com assistência de Claude (Anthropic). Baseado no excelente trabalho do [devmfc/debian-on-amlogic](https://github.com/devmfc/debian-on-amlogic) como ponto de partida.

## Licença

Documentação e scripts neste repositório: MIT.
Arquivos derivados de outros projetos (devmfc bootscripts) mantêm a licença original (GPL-2.0+).
