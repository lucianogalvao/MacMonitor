# MacMonitor

Monitor de sistema para a barra de menus do macOS, feito em Swift/SwiftUI.

- **CPU:** uso total e por núcleo, com histórico
- **Temperaturas:** CPU, GPU, chip, SSD e bateria (Apple Silicon)
- **Memória:** uso, pressão, comprimida e swap
- **Rede:** download/upload e IP local (escondido por padrão)
- **Disco:** espaço livre, leitura e escrita
- **Bateria:** nível, tempo restante, ciclos e saúde
- **Processos:** os que mais usam CPU e memória
- **Clima:** atual, próximas horas e 7 dias, via [Open-Meteo](https://open-meteo.com) (sem chave)

## Requisitos

- Mac com Apple Silicon (M1 ou mais novo)
- macOS 14 (Sonoma) ou mais recente
- Para compilar: Xcode ou as ferramentas de linha de comando (`xcode-select --install`)

## Compilar

```bash
./build.sh
open build/MacMonitor.app
```

## Gerar o .dmg

```bash
./make-dmg.sh
```

Gera `build/MacMonitor.dmg` com o app, um atalho para a pasta Aplicativos e o `LEIAME.txt` com as instruções de instalação.

O app usa assinatura ad-hoc, sem a conta paga de desenvolvedor da Apple. Por isso, na primeira abertura em outro Mac, o macOS bloqueia o app e é preciso liberar em **Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim**. O passo a passo completo está no [LEIAME](Resources/LEIAME.txt).

## Temperaturas

As temperaturas são lidas pelo IOHID, uma interface interna do macOS. Ela funciona sem permissões especiais, mas não é documentada pela Apple e pode mudar em atualizações do sistema. Para listar os sensores de um Mac:

```bash
swift Scripts/sensors-probe.swift
```
