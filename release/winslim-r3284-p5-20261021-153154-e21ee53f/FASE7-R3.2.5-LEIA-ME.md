# Win-Slim Suite — FASE 7 R3.2.5 / Native UI PS5.1 Logging Hotfix

## Por que esta revisão existe
Na R3.2.4 o compilador C# concluiu com sucesso e o executável foi gerado, mas o script de build falhou **depois** da compilação ao tentar registrar o resultado com `System.IO.File.AppendAllLines`. No Windows PowerShell 5.1, o array entregue à sobrecarga pode ser tratado como `Object[]`, o que torna a resolução da assinatura ambígua.

O efeito observado foi coerente com isso: o `.exe` existia e o self-test passava, porém o build interrompia antes de copiar o `.config` e antes de registrar `ExitCode: 0` no log.

## Correção R3.2.5
O logger do build agora usa somente assinaturas não ambíguas:

- `System.IO.File.WriteAllText(path, string, encoding)`
- `System.IO.File.AppendAllText(path, string, encoding)`

As linhas são convertidas explicitamente para texto antes da gravação. Isso remove a dependência de binding de `IEnumerable<string>` do PowerShell 5.1.

Também foi adicionado um guard após `Copy-Item` para confirmar que `WinSlim.UI.Native.R3.2.5.exe.config` realmente existe.

## O que não mudou
- Planner / PlannerOptimized
- Transaction R13 / TransactionOptimized
- PresetRuntime / Preview / Providers
- 230 tweaks
- Presets 105 / 129 / 168
- 16 overlays condicionais
- contrato visual e animações da Native UI
- arquitetura read-only desta etapa

## Teste
```powershell
cd "D:\Desktop\winslim_fase7_r3_2_5"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\tests\Test-Fase7-R3.2.5-NativeUI.ps1
```

Resultado esperado:

`FASE 7 R3.2.5 APROVADA`

Depois execute:

`Executar-WinSlim-R3.2.5.bat`

## Critério para avançar
Só avançar para a próxima etapa funcional da UI quando:
1. o gate estiver 100% verde;
2. o executável abrir sem exceção;
3. o layout estiver estável em DPI/resize;
4. o consumo em idle e as transições estiverem dentro do comportamento esperado.
