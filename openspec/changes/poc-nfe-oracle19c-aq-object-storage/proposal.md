## Why

Os XMLs históricos de NF-e hoje permanecem como CLOB no Oracle AI Database 26ai, concentrando volume de armazenamento no banco sem um processo controlado para transferi-los ao OCI Object Storage. A PoC deve validar uma migração confiável, observável e reversível, preservando o Oracle como catálogo e garantindo que nenhum XML de origem seja removido sem reconciliação e aprovação humana explícita.

## What Changes

- Introduzir seleção histórica de NF-es elegíveis em batches limitados, com criação atômica do item de controle e da mensagem Oracle Transactional Event Queue (TEQ).
- Introduzir processamento concorrente por workers PL/SQL/DBMS_SCHEDULER que enviam somente referências pequenas pela TEQ, convertem o CLOB em UTF-8 e gravam o conteúdo no OCI Object Storage com chave determinística.
- Introduzir idempotência, retry controlado pela TEQ, tratamento de exception queue, verificação por tamanho e SHA-256, reconciliação e controles de pausa/backpressure.
- Introduzir trilha de auditoria, métricas operacionais e relatórios de reconciliação por batch.
- Introduzir um fluxo manual e segregado de aprovação e purge: workers não podem alterar `XML_CLOB`; o purge somente pode ocorrer em batches reconciliados, aprovados e auditados.
- Manter fora de escopo a alteração do fluxo de novas NF-es, transporte de XML no payload da fila, integrações Kafka e purge automático.

## Capabilities

### New Capabilities

- `nfe-historical-migration`: seleção e admissão transacionais de NF-es históricas em batches para a Oracle Transactional Event Queue.
- `nfe-object-storage-transfer`: processamento idempotente de referências TEQ, transferência UTF-8 ao OCI Object Storage e verificação de integridade.
- `nfe-migration-operations`: reconciliação, observabilidade, controle operacional, exceções e tratamento de falhas da migração.
- `nfe-purge-governance`: aprovação humana, segregação de privilégios e purge manual auditável dos XMLs de origem.

### Modified Capabilities

Nenhuma. O repositório ainda não possui especificações OpenSpec estabelecidas.

## Impact

- Afeta o Oracle AI Database 26ai, Oracle Transactional Event Queue, `DBMS_SCHEDULER`, `DBMS_CLOUD`, schemas e privilégios de banco.
- Requer bucket, IAM/credential, conectividade e políticas de segurança no OCI Object Storage.
- Cria tabelas de controle, auditoria e reconciliação, packages PL/SQL, filas e jobs inicialmente desabilitados.
- Não altera o caminho crítico de inserção nem o modelo transacional de novas NF-es nesta fase.
