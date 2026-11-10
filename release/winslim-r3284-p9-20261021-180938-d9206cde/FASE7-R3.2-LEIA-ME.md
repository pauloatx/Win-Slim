# Win-Slim Suite — FASE 7 R3.2 / Native UI Foundation

## Objetivo
Migrar a camada de apresentação da FASE 7 para um host **C# WPF nativo**, preservando integralmente o backend PowerShell aprovado. O designer oficial continua sendo a referência visual enviada pelo usuário: janela compacta, sidebar estreita, painéis densos, tema preto/cinza e laranja Win-Slim.

## O que é funcional nesta revisão
- shell C# WPF compilado;
- navegação com transição curta (fade + deslocamento);
- Presets Equilibrado / Gamer / Extremo;
- 16 overlays condicionais como botões/toggles interativos;
- estado ativo destacado em laranja;
- elegibilidade de hardware consumida do backend aprovado;
- consentimento de risco Alto preservado;
- resumo em tempo real: preset, overlays, total, risco e fingerprint;
- Dashboard lê snapshot e métricas reais por bridge;
- Preview / Aplicação / Conclusão / Backup / Personalizado / Detalhe / Análise / Configurações já possuem o esqueleto visual da referência.

## O que NÃO é feito nesta revisão
A R3.2 **não aplica tweaks**, não inicia Planner, Preview transacional, Transaction ou Providers. Os botões de Apply dos protótipos permanecem desabilitados. A ligação transacional continua reservada para as fases previstas no roadmap.

## Arquitetura
`C# WPF Native UI -> bridge PowerShell persistente -> PresetRuntime / RuntimePromotion -> backend aprovado`

O bridge permanece read-only nesta etapa. A UI não contém primitivas de mutação do Windows.

## Decisões de desempenho/estabilidade
- `AllowsTransparency=False`: evita o custo de janela WPF layered/transparente;
- sem blur/acrílico contínuo;
- animações apenas durante transições/interações, ~160–190 ms;
- um único processo PowerShell persistente, evitando spawn a cada clique;
- comunicação assíncrona por JSON line protocol;
- métricas a cada 3 s somente quando o Dashboard está visível e a janela não está minimizada;
- processo principal `asInvoker`; elevação ficará isolada no worker transacional quando chegar a fase de Apply;
- DPI Per-Monitor V2 via manifest;
- sem dependências NuGet e sem necessidade de Visual Studio para compilar.

## Validar no Windows
Extraia a pasta e execute em Windows PowerShell 5.1:

```powershell
cd "D:\Desktop\winslim_fase7_r3_2"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\tests\Test-Fase7-R3.2-NativeUI.ps1
```

O gate compila a Native UI usando o `csc.exe` do .NET Framework do próprio Windows, testa o bridge, carrega o XAML pelo runtime WPF real e executa um self-test do EXE.

Se terminar com `FASE 7 R3.2 APROVADA`, abra:

```text
Executar-WinSlim-R3.2.bat
```

## Validação visual prioritária
1. densidade e proporção da janela;
2. navegação e suavidade das transições;
3. cards Equilibrado / Gamer / Extremo;
4. overlays: clique, destaque laranja, bloqueio/elegibilidade e consentimento Alto;
5. consumo de CPU em idle e com a janela minimizada;
6. comportamento em escala DPI diferente de 100%.
