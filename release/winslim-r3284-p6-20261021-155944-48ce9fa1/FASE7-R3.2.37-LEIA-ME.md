# Win-Slim Suite — R3.2.37

Padronização de nomes em todo o pacote: interface, metadados do catálogo, identificadores de três ajustes avançados, caminhos de arquivos, código ativo e histórico empacotado, testes e documentação. O catálogo de jogos/workloads passou a Game-Workload.json e o de ajustes avançados a Advanced-Catalog.json. Os três identificadores avançados usam o prefixo WS-ADV. Não foram removidos ajustes nem alteradas suas operações.

Os arquivos das revisões anteriores no pacote também receberam a padronização, para que não reintroduzam as referências removidas. Suas especificações de integridade foram recalculadas e mantêm a verificação de hashes após a transformação. Os pacotes anteriores já entregues não foram modificados. Esta revisão constitui uma nova base de nomenclatura, sem afirmar equivalência byte a byte à antiga.

Presets JSON exportados anteriormente que contenham os três identificadores antigos devem ser salvos novamente a partir da seleção na nova versão. A validação de importação continua estrita.

Extraia em pasta nova e execute Validar-Padronizacao-R3.2.37.bat. Confira a seleção dos presets e overlays, Personalizado, detalhes e pré-visualização. Catálogo 230 e contagens dos presets 105/129/168 preservados. Execução na interface continua em modo de consulta/demonstração.

R3.2.36 passou no gate Windows enviado pelo usuário (resultado 0). Foram feitas verificações locais de ausência das referências removidas, JSON/XML, nomes dos controles, estrutura C#, igualdade dos ajustes antes/depois da transformação, integridade das especificações e do ZIP. Compilação, carregamento WPF e pipeline PowerShell devem ser validados no Windows.
