# AmlBoot B13

> Debian 13 autônomo no eMMC interno de uma BTV B13 (Amlogic S905X4).

Engenharia reversa do bootloader vendor de uma TV Box BTV B13 pra rodar Debian 13 + XFCE direto do eMMC interno — sem pendrive, sem toothpick, ligar e usar.

## Conteúdo

| Arquivo | Pra quê |
|---|---|
| **[`TUTORIAL.md`](TUTORIAL.md)** | Procedimento passo a passo replicável em outra B13 |
| **[`DIARIO.md`](DIARIO.md)** | Diário técnico completo do processo, descobertas, e lições |
| `scripts/` | Arquivos auxiliares (configs, scripts u-boot, sketch ESP32) |

## Quem deve usar isso

- **Tem uma BTV B13** (S905X4) e quer rodar Linux nela → ver `TUTORIAL.md`
- **Quer entender como foi feito** → ver `DIARIO.md`
- **Quer adaptar pra outro modelo de TV box Amlogic** → ambos

## Status

- ✅ Boot autônomo do eMMC funcionando
- ✅ XFCE com aceleração GPU otimizado
- ✅ Ethernet, SSH, HDMI, áudio
- ❌ WiFi (chip MT7668, requer DTB específico)
- 🚧 Versão 2: pendrive auto-installer (sem UART) — em desenvolvimento

## Hardware testado

| | |
|---|---|
| TV Box | BTV B13 |
| SoC | Amlogic S905X4 (SC2) |
| RAM | 2 GB |
| Storage | 16 GB eMMC |

## Créditos

Procedimento desenvolvido por **Gabriel Lima** com assistência de Claude (Anthropic). Baseado no excelente trabalho do [devmfc/debian-on-amlogic](https://github.com/devmfc/debian-on-amlogic) como ponto de partida.

## Licença

Documentação e scripts neste repositório: MIT.
Arquivos derivados de outros projetos (devmfc bootscripts) mantêm a licença original (GPL-2.0+).
