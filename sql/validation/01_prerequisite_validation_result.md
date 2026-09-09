# Resultado da validação de pré-requisitos

**Data da evidência:** 2026-09-04  
**Ambiente:** `PDB_POCRT_02` em `READ WRITE`  
**Banco:** Oracle AI Database 26ai EE Extreme Performance, versão `23.26.3.0.0`  
**Parâmetro `compatible`:** `23.6.0`

## Evidências aprovadas

- `DBMS_CLOUD` e seu package body estão `VALID`, expostos pelo sinônimo público para `C##CLOUD$SERVICE`.
- As sobrecargas BLOB de `DBMS_CLOUD.PUT_OBJECT` e `DBMS_CLOUD.GET_OBJECT` estão disponíveis.
- `DBMS_AQ` e `DBMS_AQADM` estão `VALID`.
- As APIs TEQ requeridas estão disponíveis: `DBMS_AQADM.CREATE_TRANSACTIONAL_EVENT_QUEUE`, `DBMS_AQADM.CREATE_EQ_EXCEPTION_QUEUE` e `DBMS_AQADM.START_QUEUE`; as sobrecargas de `DBMS_AQ.ENQUEUE` e `DBMS_AQ.DEQUEUE` também estão presentes.
- A sessão usada na validação possui os papéis `AQ_ADMINISTRATOR_ROLE`, `AQ_USER_ROLE` e `SCHEDULER_ADMIN`.
- As ACLs visíveis permitem `CONNECT`, `HTTP` e `RESOLVE` em HTTPS/443 para o host curinga `*`.

## Resultado

**GO** para criar os artefatos de banco e implementar a PoC sobre Oracle AI Database 26ai e TEQ.

**Restrição inicial, posteriormente resolvida:** a primeira consulta a `USER_CREDENTIALS` retornou zero credentials na sessão validada. Antes do smoke test, foi criada uma credential aprovada com acesso ao bucket `POC_RT` no namespace `idzvuvikb5ym`, região `us-ashburn-1`.

## Evidência de transferência autenticada

Após a criação da credential `NFE_OBJECT_STORAGE_S3_CRED` no `NFE_OWNER` e da ACL para o endpoint dedicado S3-compatible, o smoke test concluiu com sucesso em 2026-09-04:

- upload e download autenticados usando `DBMS_CLOUD.PUT_OBJECT` e `DBMS_CLOUD.GET_OBJECT`;
- objeto de evidência: `nfe-poc/preflight/dbms-cloud-5aad238d250cbf3ae063e60010ac2038.txt` no bucket `POC_RT`;
- SHA-256 verificado: `9031CF484799E4CD3F5702BE631F874FDBE026F4900F659A70EF01E9CA909D58`.

O resultado remove o bloqueio de transferência autenticada; credenciais e valores secretos não foram registrados.

## Evidência da Transactional Event Queue

Em 2026-09-04, `NFE_OWNER` criou e iniciou `NFE_MIGRATION_Q` (TEQ com payload `RAW` e `MAX_RETRIES = 3`) e `NFE_MIGRATION_EX_Q`. O teste controlado concluiu com:

`PASS: RAW TEQ enqueue/dequeue and retry forwarding to exception queue succeeded.`

O teste confirmou consumo com `REMOVE`/`ON_COMMIT` e encaminhamento à exception queue após três rollbacks deliberados. O produtor deve definir explicitamente a propriedade `exception_queue` em cada envelope de trabalho; a simples criação da exception queue não a associa automaticamente à mensagem.

## Baseline técnico pré-carga

Coleta executada como `SYS` em `PDB_POCRT_02` em 2026-09-04 18:53 UTC por `03_capture_poc_baseline.sql`:

- `NFE_OWNER.POC_NFE_DOCUMENT` contém `0` documentos e `0` XMLs; não há ainda distribuição temporal ou por situação para caracterizar o dataset.
- A TEQ `NFE_MIGRATION_Q` está habilitada para enqueue/dequeue, com `MAX_RETRIES = 3`; `NFE_MIGRATION_EX_Q` está presente.
- `STREAMS_POOL_SIZE = 0` e `SGA_TARGET = 0`; o Streams Pool alocado apresentou `65.736.584` bytes de memória livre no instante da coleta.
- A coleta de `V$UNDOSTAT` retornou retenção ajustada de `900` segundos; os contadores acumulados de I/O e redo foram preservados na saída da execução.

Este é somente um baseline pré-carga. A tarefa de benchmark exige uma nova coleta antes de processar um dataset representativo de XMLs.

## Dataset sintético representativo da PoC

Em 2026-09-04, `NFE_OWNER` carregou e verificou 100 documentos sintéticos não fiscais para a PoC:

- 100 XMLs presentes, com emissões entre `2025-03-09` e `2026-08-19`;
- 60 XMLs pequenos de `2.088` caracteres, 30 médios de `20.040` e 10 grandes de `200.040`;
- situações: 77 `AUTORIZADA`, 10 `CANCELADA` e 13 `DENEGADA`.

As chaves têm o prefixo reservado de teste `000020260904`; a carga é idempotente e não representa documentos fiscais reais.

## Baseline com dataset representativo

Nova coleta em `PDB_POCRT_02` às 18:56 UTC de 2026-09-04, após a carga sintética:

- 100 documentos e 100 XMLs, totalizando `2.726.880` caracteres; média de `27.269` e máximo de `200.040` caracteres;
- distribuição por 18 meses, de março de 2025 a agosto de 2026; cada mês contém 5 ou 6 documentos;
- 77 `AUTORIZADA`, 13 `DENEGADA` e 10 `CANCELADA`;
- contadores acumulados no instante da coleta: `112.841.728` bytes de leitura física, `15.384.576` bytes de escrita física e `86.126.824` bytes de redo;
- `V$UNDOSTAT` reportou retenção ajustada de 900 segundos e o Streams Pool manteve `65.736.584` bytes livres;
- `NFE_MIGRATION_Q` permaneceu habilitada com `MAX_RETRIES = 3` e não havia itens de migração admitidos.

Os valores de I/O e redo são contadores de instância e servem como ponto de comparação para o benchmark subsequente; não são atribuídos exclusivamente à carga sintética.

## Evidência de controle de admissão

Em 2026-09-04, `NFE_OWNER` implantou `PKG_NFE_PIPELINE_CONFIG` e executou com sucesso o teste rollback-only de configuração. A leitura de configuração permitiu uma admissão elegível, a pausa bloqueou a admissão seguinte, e a reversão do teste preservou a configuração e o backlog confirmado.

## Evidência de criação de batch

Em 2026-09-04, `NFE_OWNER` validou `PKG_NFE_SELECTION`: um batch com data de corte futura foi rejeitado e o batch válido `2` foi persistido com limites e critérios JSON auditáveis, sem seleção ou enqueue de documentos.

## Evidência de seleção histórica

Em 2026-09-04, `NFE_OWNER` validou a seleção de candidatos elegíveis para o batch `2`. Cada candidato recebeu object key determinística no formato `nfe/YYYY/MM/<chave-nfe>.xml`; um item de controle transitório foi excluído da seleção subsequente e revertido ao fim do teste.

## Evidência de admissão atômica

Em 2026-09-04, `NFE_OWNER` validou `PKG_NFE_MIGRATION`: o rollback de uma admissão não deixou item de controle nem mensagem confirmada; o commit seguinte tornou visíveis conjuntamente um item `QUEUED` e seu envelope de referência RAW na TEQ. O envelope contém somente referências e define `NFE_MIGRATION_EX_Q` como exception queue.

## Evidência de admission control

Em 2026-09-04, `NFE_OWNER` executou `16_verify_nfe_admission_control.sql` com sucesso. O teste rollback-only confirmou os bloqueios por status de batch, pausa global, limite do batch e limite de itens em voo. Após a retomada, o acervo de itens e mensagens TEQ já confirmados permaneceu inalterado.

## Evidência de conversão e integridade de XML

Em 2026-09-04, `NFE_OWNER` executou `18_verify_nfe_transfer_conversion.sql` com sucesso. A conversão de CLOB para BLOB em `AL32UTF8`, o tamanho em bytes e o SHA-256 permaneceram estáveis para XMLs pequeno, médio e grande; a amostra Unicode explícita confirmou a codificação UTF-8 e os LOBs temporários foram liberados.

## Evidência de dequeue e validação do envelope

Em 2026-09-04, `NFE_OWNER` executou `20_verify_nfe_worker_dequeue.sql` com sucesso. Um envelope TEQ válido carregou o item de controle e o XML na mesma transação do dequeue; um envelope com versão inválida foi rejeitado e não alterou o item para `VERIFIED`.

## Evidência de upload para Object Storage

Em 2026-09-04, `NFE_OWNER` executou `21_verify_nfe_object_upload.sql` com sucesso. O item de controle `4` foi convertido e gravado por `DBMS_CLOUD.PUT_OBJECT` na chave determinística persistida no prefixo do bucket, com tamanho e SHA-256 de origem registrados; a API validada não retornou ETag ou ID de versão.

## Evidência de verificação forte do objeto

Em 2026-09-04, `NFE_OWNER` executou `22_verify_nfe_object_integrity.sql` com sucesso. A injeção transitória de SHA-256 divergente foi rejeitada com rollback; após download, igualdade de tamanho e hash, o item `4` alcançou `VERIFIED`.

## Evidência de idempotência de objeto

Em 2026-09-04, `NFE_OWNER` executou `23_verify_nfe_object_idempotency.sql` com sucesso. Após `PUT_OBJECT` seguido de rollback Oracle, a entrega repetida reutilizou a mesma chave determinística quando o objeto era idêntico. Um objeto preexistente divergente foi marcado `EXCEPTION` sem sobrescrita; as linhas e a auditoria append-only foram preservadas como evidência.

## Evidência de exception queue

Em 2026-09-04, `NFE_OWNER` executou `26_verify_nfe_exception_monitor.sql` com sucesso. Após exceder `MAX_RETRIES`, o monitor preservou a correlação, marcou o item como `EXCEPTION` e registrou o alerta auditável.

## Evidência de jobs agendados

Em 2026-09-08, `NFE_OWNER` executou `27_create_nfe_scheduler_jobs.sql` e `28_verify_nfe_scheduler_jobs.sql` com sucesso. Os jobs de seleção, worker e reconciliação foram criados desabilitados; os runners limitados encerraram com segurança em pausa ou sem mensagem disponível.

## Evidência de benchmark

Em 2026-09-08, quatro coortes equivalentes de 20 documentos sintéticos foram executadas sem backlog, falhas ou exceções. Latência p50/p95/p99: 1 worker `153/155/155` s; 2 workers `22/24/24` s; 4 workers `22/24/24` s; 8 workers `26,5/31/31` s. A recomendação da PoC é 2 workers com `MAX_INFLIGHT_MESSAGES = 100`. O usuário aceitou explicitamente que CPU, I/O e redo não foram mensurados durante as janelas de execução; as métricas coletadas após as rodadas estavam ociosas e não foram usadas para atribuição de impacto.

## Limitações da evidência

A execução foi feita como `SYS`; ela confirma as capacidades do PDB, mas não valida os privilégios efetivos do futuro `NFE_MIGRATION_RUNTIME`. Essa validação permanece coberta pelas tarefas de provisionamento de schemas e privilégios.
