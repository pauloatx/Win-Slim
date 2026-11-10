# Win-Slim Suite — FASE 7 R3.2.1 / Native UI Hotfix

## Objetivo
Corrigir exclusivamente as falhas encontradas no gate R3.2 no Windows, mantendo a arquitetura nativa C# + WPF e o backend PowerShell aprovado sem regressao.

## Falhas corrigidas
A R3.2 falhou em tres grupos: contagem de chips condicionais, passagem de `ProfilesJson` pelo argv do Windows PowerShell 5.1 e compilacao do host C# sem diagnostico visivel. A R3.2.1 trata cada grupo separadamente.

### 1. Overlays
A tela continua com os 16 overlays condicionais aprovados. O toggle de **Modo desenvolvedor** em Configuracoes agora usa um estilo proprio (`SettingsSwitch`) e nao e mais contado como overlay.

### 2. Bridge
O modo servidor usado pela UI continua usando JSON line protocol por stdin/stdout. O modo one-shot dos testes agora possui parser tolerante para o caso em que o Windows PowerShell 5.1 remove as aspas internas de um array JSON de um unico item ao montar argv.

### 3. Build nativo
O build usa o `csc.exe` do .NET Framework 4.x com **response file**, evitando problemas de quoting da expansao de argumentos nativos do PowerShell 5.1. Todo retorno do compilador e salvo em:

`logs\build-native-r3.2.1.log`

O host solicita DPI Per-Monitor V2 programaticamente antes da inicializacao do WPF e possui fallback para DPI aware legado. Assim, a compilacao nao depende de incorporar um manifest customizado nesta etapa.

## Arquitetura preservada
`C# WPF Native UI -> bridge PowerShell persistente -> RuntimePromotion / PresetRuntime -> backend aprovado`

A R3.2.1 permanece **read-only**. Nao chama Planner validation, Preview transacional, Transaction ou Providers de mutacao.

## Validacao no Windows
```powershell
cd "D:\Desktop\winslim_fase7_r3_2_1"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\tests\Test-Fase7-R3.2.1-NativeUI.ps1
```

O gate agora mostra o diagnostico do compilador no console se o build falhar e tambem preserva o log completo.

Se terminar com `FASE 7 R3.2.1 APROVADA`, execute:

`Executar-WinSlim-R3.2.1.bat`

## Validacao visual
Priorize:
1. abertura e estabilidade da janela;
2. 16 overlays clicaveis, com ativo em laranja;
3. cards Equilibrado / Gamer / Extremo;
4. consentimento visual de overlays de risco Alto;
5. transicoes curtas e sem travamento;
6. CPU em idle e com janela minimizada;
7. escala DPI 100%, 125% ou 150% se disponivel.
