# Separação de pacotes — correção após AV-20261021-001

O ZIP P9 preservado é um pacote técnico de validação com fontes e scripts que compilam testes. Não contém `PresentMonHarness.exe` pronto, mas executá-lo pelo validador gera auxiliares no computador. A investigação está em [INCIDENTE-KASPERSKY-R3.2.84.md](INCIDENTE-KASPERSKY-R3.2.84.md).

O empacotador agora exige `--profile` explícito na CLI:

- `validation`: preserva fontes/cadastro/scripts para desenvolvedores e validação técnica, com identificação clara em `PACKAGE-PROFILE.json`. Binários compilados exigem lista revisada de caminho/hash. Não é distribuição somente de runtime.
- `runtime`: exige `--runtime-manifest <caminho relativo>` e copia apenas os arquivos/hashes dessa lista. Não inclui `tests`, `tools`, `logs`, fontes C#/Python, builders, validadores ou arquivos de depuração/arquivos compactados. Não compila testes ao abrir. O manifesto da distribuição real ainda precisa de revisão das dependências e integração após a revisão AV; apenas fixtures foram empacotadas nesta rodada.

Formato da lista: JSON com `schemaVersion: 1` e `files` mapeando caminhos relativos para SHA-256. Caminhos, hashes, fontes e cadastro único são verificados; arquivos selecionados são novamente conferidos no ZIP antes da substituição atômica. Binários fora dos caminhos de produção permitidos, sem hash ou com hash divergente são rejeitados. A origem de um binário não é comprovada apenas pelo nome: a revisão e o hash do manifesto continuam necessários. Diagnósticos ZIP em validação só podem conter formatos de evidência permitidos, sem executáveis ou outros arquivos compactados opacos.

Uma política de incidente em investigação bloqueia a publicação de ambos os perfis; o ZIP anterior permanece intacto. Não há opção CLI de ignorar esse bloqueio. O perfil não é um mecanismo de liberação AV.

Python é ferramenta de desenvolvimento/empacotamento. O runtime final não deve depender dele nem da compilação de testes no computador do usuário. Os testes do empacotador usam arquivos inertes e não inicializam o aplicativo nem o coletor.

O gate do projeto continua obrigatório antes de qualquer novo ZIP de aplicativo. Nesta rodada, ele permanece bloqueado pelo incidente; nenhum novo pacote de aplicativo foi publicado.
