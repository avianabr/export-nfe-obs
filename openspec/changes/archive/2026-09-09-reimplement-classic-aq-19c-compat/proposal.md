## Why

A PoC baseada em TEQ no Oracle AI Database 26ai encontrou um incidente AQ
`ORA-00600` e, depois, mensagens que apareciam como `READY` mas não eram
entregues ao worker. É necessário isolar a investigação e reimplementar o
transporte de trabalho com Oracle Advanced Queuing clássico, usando uma shared
queue compatível com Oracle 19c, para validar o fluxo de migração sem depender
do caminho TEQ afetado.

## What Changes

- Substituir o transporte TEQ da PoC por uma fila AQ clássica compartilhada,
  com queue table e exception queue compatíveis com o contrato Oracle 19c.
- Preservar o envelope RAW de referências pequenas, a admissão atômica e o
  dequeue transacional `REMOVE`/`ON_COMMIT`.
- Reimplementar workers, retries e monitoramento de exceções sobre a API AQ
  clássica, mantendo a verificação de integridade e a segregação do purge.
- **BREAKING**: os jobs e packages de runtime deixarão de depender de
  `NFE_MIGRATION_Q` como TEQ; filas, grants e diagnósticos atuais deverão ser
  substituídos após uma implantação controlada.
- Tratar AQ clássico como caminho de compatibilidade da PoC no 26ai, usando
  apenas APIs e semânticas compatíveis com 19c, e registrar o resultado do
  go/no-go antes de qualquer expansão. AQ sharded/TEQ não fará parte desse
  caminho alternativo.

## Capabilities

### New Capabilities

- `nfe-classic-aq-transport`: contrato de shared queue AQ clássica para
  admissão, entrega, retry, exception queue e operação compatível com 19c.

### Modified Capabilities

Nenhuma. As especificações TEQ existentes ainda pertencem à mudança de PoC
anterior não arquivada; esta mudança define o transporte alternativo de forma
isolada.

## Impact

- Afeta scripts DDL de fila, packages `PKG_NFE_MIGRATION`/`PKG_NFE_WORKER`,
  monitor de exceções, jobs `DBMS_SCHEDULER`, grants AQ e scripts de validação.
- Requer validação da API AQ clássica, privilégio e semântica de retry na RU
  23.26.3.0.0, sem descartar os artefatos TEQ/ADR usados no chamado Oracle.
- Não altera o catálogo Oracle, o formato de objeto no Object Storage, nem os
  controles de aprovação e purge.
