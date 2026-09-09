# Proposta de Prova de Conceito

## Migração de XML de NF-e do Oracle Database 19c para OCI Object Storage com Oracle Advanced Queuing

**Versão:** 1.0  
**Baseline tecnológico:** Oracle Database 19c, Oracle Advanced Queuing (Sharded AQ), PL/SQL, `DBMS_SCHEDULER`, `DBMS_CLOUD` e OCI Object Storage  
**Escopo da primeira implantação:** exclusivamente NF-es já existentes no Oracle Database

---

## 1. Resumo executivo

Esta Prova de Conceito (PoC) validará a migração controlada de XMLs históricos de Nota Fiscal Eletrônica (NF-e), inicialmente armazenados em uma coluna `CLOB` no Oracle Database 19c, para o OCI Object Storage.

O Oracle continuará sendo o catálogo e o plano de controle da solução: nele permanecerão os dados relacionais da NF-e, o estado de cada migração, os lotes, a auditoria e a referência determinística do objeto. O conteúdo XML será enviado ao Object Storage por workers PL/SQL executados pelo `DBMS_SCHEDULER`. A distribuição assíncrona do trabalho será feita por Oracle Advanced Queuing, preferencialmente com Sharded AQ disponível no 19c.

A fila transportará apenas uma referência pequena, como `controlId`, `nfeId`, `batchId` e a versão do contrato. O XML/CLOB nunca será colocado no payload da AQ. O worker buscará o conteúdo na tabela de NF-e, converterá o `CLOB` para `BLOB` em UTF-8 e chamará `DBMS_CLOUD.PUT_OBJECT`.

O desenho separa explicitamente:

- a seleção histórica e a admissão de trabalho;
- a entrega da mensagem pela AQ;
- o upload e a verificação do objeto;
- a reconciliação do batch;
- a aprovação humana;
- o purge do XML original.

O purge **não faz parte do pipeline automático**. Ele só poderá ocorrer depois de uma aprovação humana explícita por batch, registrada por `APPROVED_BY` e `APPROVED_AT`. O pacote e os privilégios de purge serão separados dos workers de migração, de forma que a identidade de execução dos workers não consiga apagar ou zerar o `CLOB`.

---

## 2. Objetivos da PoC

A PoC deverá demonstrar:

1. seleção repetível de NF-es históricas por critérios configuráveis;
2. criação atômica do controle de migração e da mensagem AQ;
3. processamento concorrente por workers PL/SQL;
4. upload para OCI Object Storage por `DBMS_CLOUD.PUT_OBJECT`;
5. idempotência após timeout, rollback, reinício ou entrega repetida;
6. retry controlado pela AQ, limite de tentativas e tratamento por exception queue;
7. controle de vazão e backpressure sem sobrecarregar o banco ou o Object Storage;
8. verificação de tamanho e SHA-256 do conteúdo recuperado do Object Storage;
9. reconciliação completa por batch;
10. observabilidade operacional, auditoria e capacidade de pausa/retomada;
11. human gate obrigatório antes do purge;
12. separação efetiva de código, identidade e privilégios entre migração e purge.

### 2.1 Critérios de sucesso

- 100% dos itens marcados como `VERIFIED` possuem objeto recuperável, tamanho esperado e SHA-256 igual ao conteúdo de origem convertido em UTF-8.
- Um retry não cria objetos logicamente distintos para a mesma NF-e.
- Uma falha entre o upload e o commit é recuperada sem perda do documento.
- Mensagens que excedem `MAX_RETRIES` são identificáveis e tratáveis operacionalmente.
- O pipeline pode ser pausado e retomado sem nova descoberta de todo o acervo.
- É possível reduzir a vazão por tamanho de onda, número de workers e parâmetros de dequeue.
- Nenhum XML é removido sem batch reconciliado e aprovação humana explícita.
- O usuário dos workers não possui privilégio para alterar `POC_NFE_DOCUMENT.XML_CLOB`.
- A trilha de auditoria identifica quem aprovou, quando aprovou, qual evidência foi usada e quem executou o purge.

---

## 3. Escopo

### 3.1 Incluído

- NF-es já existentes no Oracle Database antes da execução da primeira implantação;
- modelo de dados simplificado para NF-e com XML em `CLOB`;
- seleção histórica em ondas/batches;
- tabela de controle por documento e tabela de batch;
- AQ/Sharded AQ no Oracle Database 19c;
- payload pequeno por referência;
- workers PL/SQL agendados com `DBMS_SCHEDULER`;
- conversão `CLOB` UTF-8 para `BLOB`;
- upload com `DBMS_CLOUD.PUT_OBJECT`;
- retry, `MAX_RETRIES` e exception queue;
- verificação, reconciliação, métricas e auditoria;
- aprovação humana por batch;
- purge manual, segregado e auditado.

### 3.2 Fora de escopo nesta primeira implantação

- interceptar ou alterar a transação que insere novas NF-es;
- trigger de enqueue para novos inserts;
- fluxo contínuo de novas NF-es;
- `INSTEAD OF INSERT` ou alteração do caminho crítico da aplicação;
- Kafka, Kafka Connect ou clientes Kafka;
- APIs e semânticas modernas de TxEventQ de versões posteriores;
- promessa de consumer groups, rebalanceamento automático ou compatibilidade Kafka;
- purge automático ao final do upload ou da verificação;
- definição definitiva de retenção legal/fiscal;
- camada transparente de leitura/cache para aplicações legadas, que poderá ser tratada em fase posterior.

---

## 4. Premissas e decisões de arquitetura

1. Oracle Database 19c é o baseline mínimo.
2. Os XMLs são imutáveis depois da emissão/recepção.
3. Cada `CHAVE_NFE` identifica de forma única o documento da PoC.
4. O Object Storage é o destino durável do conteúdo migrado; o Oracle mantém o catálogo e o controle.
5. Oracle Database e Object Storage não formam uma única transação ACID distribuída.
6. Consistência será obtida por estado explícito, chave determinística, idempotência, verificação e reconciliação.
7. O payload da AQ contém somente referências e metadados pequenos. Não contém XML, `CLOB` ou `BLOB`.
8. O `INSERT` do controle e o `ENQUEUE` serão feitos na mesma transação Oracle, com visibilidade da mensagem no commit.
9. O dequeue, as mudanças de estado finais e o commit da mensagem serão coordenados na transação do worker.
10. Uma falha após `PUT_OBJECT` e antes do commit pode causar nova tentativa; isso é esperado e tratado pela chave determinística.
11. A quantidade selecionada por onda e a quantidade em voo serão limitadas.
12. O purge só ocorrerá depois de verificação, reconciliação e aprovação humana explícita por batch.
13. Os workers de upload/verificação não terão privilégio para modificar a coluna `XML_CLOB`.
14. A disponibilidade do pacote `DBMS_CLOUD`, sua versão, credenciais, ACLs e conectividade deve ser validada no ambiente 19c alvo antes da PoC.

### 4.1 Por que não transportar o XML na fila

A Sharded AQ usa memória do Streams Pool para seu message cache. Mensagens pequenas favorecem throughput, paralelismo e uso previsível de memória. Colocar XMLs grandes na fila duplicaria temporariamente o conteúdo, aumentaria redo/undo e trabalharia contra esse modelo.

O contrato lógico recomendado é:

```json
{
  "eventType": "NFE_UPLOAD_REQUEST",
  "version": 1,
  "controlId": 987654,
  "nfeId": 123456,
  "batchId": 2026090001
}
```

O JSON é apenas um envelope serializado em UTF-8 para payload `RAW`. No 19c, a solução não depende de tipo de dado nativo `JSON` nem de APIs Kafka.

---

## 5. Arquitetura proposta

```text
                         PIPELINE AUTOMÁTICO E REVERSÍVEL

  +--------------------+       +--------------------------+
  | POC_NFE_DOCUMENT   |       | NFE_MIGRATION_BATCH      |
  | XML histórico CLOB |       | critérios e contadores   |
  +----------+---------+       +-------------+------------+
             |                               |
             +---------------+---------------+
                             |
                    Selection/Admission Job
                             |
                  mesma transação Oracle
                  +----------+-----------+
                  |                      |
                  v                      v
       INSERT NFE_MIGRATION_ITEM     ENQUEUE RAW
              status=QUEUED        referência pequena
                  |                      |
                  +----------+-----------+
                             |
                           COMMIT
                             |
                             v
                    Oracle Sharded AQ 19c
                     /        |        \
                    v         v         v
                 Worker 1  Worker 2  Worker N
                    \         |         /
                     +--------+--------+
                              |
                  CLOB -> BLOB UTF-8
                              |
                   DBMS_CLOUD.PUT_OBJECT
                              |
                              v
                    OCI Object Storage
                              |
                  GET_OBJECT + hash/tamanho
                              |
                              v
                           VERIFIED
                              |
                    Reconciliação do batch
                              |
                              v
                    READY_FOR_APPROVAL

  ====================================================================
                 HUMAN GATE — FORA DO PIPELINE AUTOMÁTICO
  ====================================================================

            relatório revisado + aprovação explícita do batch
                              |
               APPROVED_BY / APPROVED_AT / evidência
                              |
                              v
                   APPROVED_FOR_PURGE
                              |
               pacote e identidade separados
                              |
                              v
                         purge manual
                              |
                              v
                           PURGED
```

### 5.1 Responsabilidades

| Componente | Responsabilidade |
|---|---|
| `POC_NFE_DOCUMENT` | Dados relacionais e XML original da PoC |
| `NFE_MIGRATION_BATCH` | Critérios, fase do lote, reconciliação e aprovação |
| `NFE_MIGRATION_ITEM` | Estado de negócio e evidência por NF-e |
| `NFE_MIGRATION_AUDIT` | Eventos operacionais e administrativos imutáveis |
| `NFE_RECONCILIATION_RUN` | Resultado consolidado de cada reconciliação |
| `NFE_MIGRATION_CONFIG` | Limites operacionais e pausa global |
| Sharded AQ | Entrega concorrente, retry e exception queue |
| `PKG_NFE_SELECTION` | Seleção histórica e enqueue atômico |
| `PKG_NFE_MIGRATION` | Dequeue, upload, verificação e atualização de estado |
| `PKG_NFE_RECONCILIATION` | Validação por item e fechamento do batch |
| `PKG_NFE_PURGE_ADMIN` | Aprovação e purge, sem participação dos workers |
| `DBMS_SCHEDULER` | Execução controlada de seleção, workers e reconciliação |
| OCI Object Storage | Armazenamento durável do XML |

---

## 6. Modelo de dados da PoC

Os DDLs a seguir são exemplos executáveis a serem ajustados para tablespaces, padrões de nomenclatura, particionamento, compressão, retenção e políticas do ambiente.

### 6.1 Tabela simplificada de NF-e

```sql
CREATE TABLE poc_nfe_document (
    nfe_id            NUMBER GENERATED BY DEFAULT AS IDENTITY,
    chave_nfe         VARCHAR2(44 CHAR) NOT NULL,
    emitente_cnpj     VARCHAR2(14 CHAR),
    destinatario_cnpj VARCHAR2(14 CHAR),
    data_emissao      TIMESTAMP(6) WITH TIME ZONE NOT NULL,
    situacao          VARCHAR2(30 CHAR) NOT NULL,
    xml_clob          CLOB,
    created_at        TIMESTAMP(6) WITH TIME ZONE
                      DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_poc_nfe_document PRIMARY KEY (nfe_id),
    CONSTRAINT uk_poc_nfe_document_chave UNIQUE (chave_nfe)
)
LOB (xml_clob) STORE AS SECUREFILE poc_nfe_xml_lob (
    COMPRESS MEDIUM
);

CREATE INDEX ix_poc_nfe_document_emissao
    ON poc_nfe_document (data_emissao, nfe_id);
```

Observações:

- o XML permanece `CLOB` para representar o cenário da PoC;
- pressupõe-se que o texto esteja em codificação válida e seja convertido para UTF-8 antes do upload;
- `SECUREFILE` e compressão devem ser validados conforme licenciamento e configuração do ambiente;
- o critério de purge será `UPDATE ... SET XML_CLOB = NULL`, nunca `DELETE` da linha fiscal.

### 6.2 Tabela de batch

```sql
CREATE TABLE nfe_migration_batch (
    batch_id                 NUMBER GENERATED BY DEFAULT AS IDENTITY,
    batch_code               VARCHAR2(50 CHAR) NOT NULL,
    status                   VARCHAR2(30 CHAR) NOT NULL,
    cutoff_date              TIMESTAMP(6) WITH TIME ZONE NOT NULL,
    max_documents            NUMBER NOT NULL,
    selection_chunk_size     NUMBER DEFAULT 1000 NOT NULL,
    criteria_json            CLOB,
    selected_count           NUMBER DEFAULT 0 NOT NULL,
    queued_count             NUMBER DEFAULT 0 NOT NULL,
    uploaded_count           NUMBER DEFAULT 0 NOT NULL,
    verified_count           NUMBER DEFAULT 0 NOT NULL,
    failed_count             NUMBER DEFAULT 0 NOT NULL,
    exception_count          NUMBER DEFAULT 0 NOT NULL,
    purged_count             NUMBER DEFAULT 0 NOT NULL,
    source_bytes             NUMBER DEFAULT 0 NOT NULL,
    object_bytes             NUMBER DEFAULT 0 NOT NULL,
    created_by               VARCHAR2(128 CHAR) NOT NULL,
    created_at               TIMESTAMP(6) WITH TIME ZONE
                             DEFAULT SYSTIMESTAMP NOT NULL,
    selection_completed_at   TIMESTAMP(6) WITH TIME ZONE,
    reconciliation_status    VARCHAR2(30 CHAR),
    reconciled_at            TIMESTAMP(6) WITH TIME ZONE,
    approved_by              VARCHAR2(128 CHAR),
    approved_at              TIMESTAMP(6) WITH TIME ZONE,
    approval_comment         VARCHAR2(1000 CHAR),
    approval_evidence_ref    VARCHAR2(500 CHAR),
    purge_started_at         TIMESTAMP(6) WITH TIME ZONE,
    purged_at                TIMESTAMP(6) WITH TIME ZONE,
    last_error               VARCHAR2(4000 CHAR),
    CONSTRAINT pk_nfe_migration_batch PRIMARY KEY (batch_id),
    CONSTRAINT uk_nfe_migration_batch_code UNIQUE (batch_code),
    CONSTRAINT ck_nfe_migration_batch_status CHECK (status IN (
        'CREATED', 'SELECTING', 'PROCESSING', 'RECONCILING',
        'READY_FOR_APPROVAL', 'APPROVED_FOR_PURGE',
        'PURGING', 'PURGED', 'BLOCKED', 'CANCELLED'
    )),
    CONSTRAINT ck_nfe_migration_batch_limit CHECK (max_documents > 0),
    CONSTRAINT ck_nfe_migration_batch_chunk CHECK (selection_chunk_size > 0),
    CONSTRAINT ck_nfe_migration_batch_approval CHECK (
        (approved_by IS NULL AND approved_at IS NULL)
        OR
        (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    ),
    CONSTRAINT ck_nfe_migration_batch_json CHECK (criteria_json IS JSON)
);
```

`CRITERIA_JSON` guarda uma cópia auditável dos parâmetros usados, por exemplo:

```json
{
  "cutoffDate": "2024-01-01T00:00:00Z",
  "situacoes": ["AUTORIZADA"],
  "maxDocuments": 100000,
  "selectionChunkSize": 1000
}
```

### 6.3 Controle por NF-e

```sql
CREATE TABLE nfe_migration_item (
    control_id         NUMBER GENERATED BY DEFAULT AS IDENTITY,
    batch_id           NUMBER NOT NULL,
    nfe_id             NUMBER NOT NULL,
    status             VARCHAR2(30 CHAR) NOT NULL,
    object_key         VARCHAR2(1024 CHAR) NOT NULL,
    object_uri         VARCHAR2(2000 CHAR) NOT NULL,
    content_type       VARCHAR2(100 CHAR) DEFAULT 'application/xml' NOT NULL,
    charset_name       VARCHAR2(30 CHAR) DEFAULT 'AL32UTF8' NOT NULL,
    source_size_bytes  NUMBER,
    object_size_bytes  NUMBER,
    source_sha256      VARCHAR2(64 CHAR),
    object_sha256      VARCHAR2(64 CHAR),
    etag               VARCHAR2(256 CHAR),
    object_version_id  VARCHAR2(512 CHAR),
    aq_msgid           RAW(16),
    business_attempts  NUMBER DEFAULT 0 NOT NULL,
    selected_at        TIMESTAMP(6) WITH TIME ZONE
                       DEFAULT SYSTIMESTAMP NOT NULL,
    enqueued_at        TIMESTAMP(6) WITH TIME ZONE,
    upload_started_at  TIMESTAMP(6) WITH TIME ZONE,
    uploaded_at        TIMESTAMP(6) WITH TIME ZONE,
    verified_at        TIMESTAMP(6) WITH TIME ZONE,
    purged_at          TIMESTAMP(6) WITH TIME ZONE,
    last_error_code    VARCHAR2(100 CHAR),
    last_error         VARCHAR2(4000 CHAR),
    last_error_at      TIMESTAMP(6) WITH TIME ZONE,
    created_at         TIMESTAMP(6) WITH TIME ZONE
                       DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at         TIMESTAMP(6) WITH TIME ZONE
                       DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_nfe_migration_item PRIMARY KEY (control_id),
    CONSTRAINT fk_nfe_migration_item_batch FOREIGN KEY (batch_id)
        REFERENCES nfe_migration_batch (batch_id),
    CONSTRAINT fk_nfe_migration_item_nfe FOREIGN KEY (nfe_id)
        REFERENCES poc_nfe_document (nfe_id),
    CONSTRAINT uk_nfe_migration_item_nfe UNIQUE (nfe_id),
    CONSTRAINT uk_nfe_migration_item_key UNIQUE (object_key),
    CONSTRAINT ck_nfe_migration_item_status CHECK (status IN (
        'QUEUED', 'UPLOADING', 'UPLOADED', 'VERIFYING',
        'VERIFIED', 'FAILED', 'EXCEPTION', 'PURGED'
    ))
);

CREATE INDEX ix_nfe_migration_item_batch_status
    ON nfe_migration_item (batch_id, status, control_id);
```

Nesta primeira implantação, `UNIQUE (NFE_ID)` impede que a mesma NF-e seja selecionada em dois batches. Se no futuro houver remigração/versionamento, o modelo deverá ganhar uma versão lógica e a unicidade será revista conscientemente.

### 6.4 Auditoria append-only

```sql
CREATE TABLE nfe_migration_audit (
    audit_id        NUMBER GENERATED BY DEFAULT AS IDENTITY,
    event_at        TIMESTAMP(6) WITH TIME ZONE
                    DEFAULT SYSTIMESTAMP NOT NULL,
    actor           VARCHAR2(128 CHAR) NOT NULL,
    actor_type      VARCHAR2(30 CHAR) NOT NULL,
    batch_id        NUMBER,
    control_id      NUMBER,
    event_type      VARCHAR2(50 CHAR) NOT NULL,
    from_status     VARCHAR2(30 CHAR),
    to_status       VARCHAR2(30 CHAR),
    correlation_id  VARCHAR2(100 CHAR),
    details_json    CLOB,
    CONSTRAINT pk_nfe_migration_audit PRIMARY KEY (audit_id),
    CONSTRAINT fk_nfe_migration_audit_batch FOREIGN KEY (batch_id)
        REFERENCES nfe_migration_batch (batch_id),
    CONSTRAINT fk_nfe_migration_audit_item FOREIGN KEY (control_id)
        REFERENCES nfe_migration_item (control_id),
    CONSTRAINT ck_nfe_migration_audit_actor CHECK (
        actor_type IN ('USER', 'SCHEDULER', 'WORKER', 'SYSTEM')
    ),
    CONSTRAINT ck_nfe_migration_audit_json CHECK (details_json IS JSON)
);

CREATE INDEX ix_nfe_migration_audit_batch
    ON nfe_migration_audit (batch_id, event_at);
```

A aplicação deverá impedir `UPDATE` e `DELETE` nessa tabela para os usuários operacionais. Retenção, proteção e exportação da auditoria devem seguir a política corporativa.

### 6.5 Execuções de reconciliação

```sql
CREATE TABLE nfe_reconciliation_run (
    reconciliation_id  NUMBER GENERATED BY DEFAULT AS IDENTITY,
    batch_id            NUMBER NOT NULL,
    status              VARCHAR2(20 CHAR) NOT NULL,
    total_count         NUMBER DEFAULT 0 NOT NULL,
    verified_count      NUMBER DEFAULT 0 NOT NULL,
    missing_object_count NUMBER DEFAULT 0 NOT NULL,
    size_mismatch_count NUMBER DEFAULT 0 NOT NULL,
    hash_mismatch_count NUMBER DEFAULT 0 NOT NULL,
    failed_count        NUMBER DEFAULT 0 NOT NULL,
    exception_count     NUMBER DEFAULT 0 NOT NULL,
    source_bytes        NUMBER DEFAULT 0 NOT NULL,
    object_bytes        NUMBER DEFAULT 0 NOT NULL,
    report_uri          VARCHAR2(2000 CHAR),
    started_at          TIMESTAMP(6) WITH TIME ZONE
                        DEFAULT SYSTIMESTAMP NOT NULL,
    completed_at        TIMESTAMP(6) WITH TIME ZONE,
    executed_by         VARCHAR2(128 CHAR) NOT NULL,
    CONSTRAINT pk_nfe_reconciliation_run PRIMARY KEY (reconciliation_id),
    CONSTRAINT fk_nfe_reconciliation_batch FOREIGN KEY (batch_id)
        REFERENCES nfe_migration_batch (batch_id),
    CONSTRAINT ck_nfe_reconciliation_status CHECK (
        status IN ('RUNNING', 'PASSED', 'FAILED')
    )
);
```

### 6.6 Configuração operacional

```sql
CREATE TABLE nfe_migration_config (
    config_id              NUMBER PRIMARY KEY,
    pipeline_paused        CHAR(1) DEFAULT 'N' NOT NULL,
    max_inflight_messages  NUMBER DEFAULT 10000 NOT NULL,
    enqueue_chunk_size     NUMBER DEFAULT 1000 NOT NULL,
    worker_count           NUMBER DEFAULT 4 NOT NULL,
    worker_idle_seconds    NUMBER DEFAULT 5 NOT NULL,
    max_worker_run_minutes NUMBER DEFAULT 30 NOT NULL,
    updated_by             VARCHAR2(128 CHAR) NOT NULL,
    updated_at             TIMESTAMP(6) WITH TIME ZONE
                           DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT ck_nfe_migration_paused CHECK (pipeline_paused IN ('Y', 'N')),
    CONSTRAINT ck_nfe_migration_inflight CHECK (max_inflight_messages > 0),
    CONSTRAINT ck_nfe_migration_workers CHECK (worker_count > 0)
);
```

---

## 7. Definição da AQ no Oracle 19c

### 7.1 Escolha conceitual

A fila principal será uma Sharded AQ single-consumer com múltiplas sessões concorrentes de dequeue. Neste contexto, “single-consumer” significa que cada mensagem deve ser processada por um consumidor lógico, não que exista apenas uma sessão worker.

O uso de Sharded AQ no 19c oferece distribuição e paralelismo nativos, mas esta proposta **não presume** semânticas Kafka de versões mais novas, como consumer groups compatíveis com Kafka ou rebalanceamento automático de partições.

### 7.2 DDL conceitual da fila e exception queue

```sql
BEGIN
    DBMS_AQADM.CREATE_SHARDED_QUEUE(
        queue_name         => 'NFE_MIGRATION_Q',
        storage_clause     => 'TABLESPACE USERS',
        multiple_consumers => FALSE,
        max_retries        => 5,
        comment            => 'Referencias pequenas para upload historico de NFe',
        queue_payload_type => 'RAW'
    );

    DBMS_AQADM.CREATE_EXCEPTION_QUEUE(
        sharded_queue_name   => 'NFE_MIGRATION_Q',
        exception_queue_name => 'NFE_MIGRATION_EX_Q'
    );

    DBMS_AQADM.START_QUEUE(
        queue_name => 'NFE_MIGRATION_Q',
        enqueue    => TRUE,
        dequeue    => TRUE
    );
END;
/
```

Parâmetros opcionais a validar por teste de carga, e não assumir como defaults universais:

```sql
BEGIN
    DBMS_AQADM.SET_QUEUE_PARAMETER(
        'NFE_MIGRATION_Q', 'SHARD_NUM', 16
    );

    DBMS_AQADM.SET_QUEUE_PARAMETER(
        'NFE_MIGRATION_Q', 'STICKY_DEQUEUE', 1
    );

    DBMS_AQADM.SET_QUEUE_PARAMETER(
        'NFE_MIGRATION_Q', 'CQ_DEQ_FLOWCONTROL', 4
    );
END;
/
```

O número de shards, o uso de sticky dequeue, o Streams Pool e o flow control devem ser definidos a partir de benchmark no ambiente real, incluindo topologia RAC quando aplicável. Mais shards não significam automaticamente mais throughput.

### 7.3 Enqueue por referência

Exemplo conceitual de enqueue com payload `RAW` contendo JSON UTF-8:

```sql
DECLARE
    l_enqueue_options    DBMS_AQ.ENQUEUE_OPTIONS_T;
    l_message_properties DBMS_AQ.MESSAGE_PROPERTIES_T;
    l_msgid              RAW(16);
    l_json               VARCHAR2(32767);
    l_payload            RAW(32767);
BEGIN
    l_json := JSON_OBJECT(
        'eventType' VALUE 'NFE_UPLOAD_REQUEST',
        'version'   VALUE 1,
        'controlId' VALUE :control_id,
        'nfeId'     VALUE :nfe_id,
        'batchId'   VALUE :batch_id
        RETURNING VARCHAR2
    );

    l_payload := UTL_I18N.STRING_TO_RAW(l_json, 'AL32UTF8');
    l_enqueue_options.visibility := DBMS_AQ.ON_COMMIT;

    DBMS_AQ.ENQUEUE(
        queue_name         => 'NFE_MIGRATION_Q',
        enqueue_options    => l_enqueue_options,
        message_properties => l_message_properties,
        payload            => l_payload,
        msgid              => l_msgid
    );

    UPDATE nfe_migration_item
       SET aq_msgid    = l_msgid,
           enqueued_at = SYSTIMESTAMP,
           updated_at  = SYSTIMESTAMP
     WHERE control_id  = :control_id;
END;
/
```

Esse bloco deve fazer parte da mesma transação que insere `NFE_MIGRATION_ITEM`. O commit é feito por chunk, não por todo o acervo.

### 7.4 Dequeue transacional

O worker usará `DBMS_AQ.DEQUEUE` com visibilidade `ON_COMMIT` e modo `REMOVE`. Em caso de sucesso, o worker atualiza o item para `VERIFIED` e faz commit; a mensagem é então removida. Em caso de falha transitória, o worker faz rollback; a mensagem volta a ficar disponível e o contador interno de retry da AQ avança conforme as regras do 19c.

Quando `MAX_RETRIES` for excedido, a mensagem deve ficar acessível pela exception queue configurada. Um monitor específico correlacionará a mensagem de exceção ao `CONTROL_ID`, marcará o item como `EXCEPTION` e abrirá alerta operacional. A PoC deve testar explicitamente esse comportamento no RU exato do ambiente.

---

## 8. Fluxo de seleção histórica

### 8.1 Criação do batch

Um usuário autorizado cria um batch com:

- data de corte;
- situações fiscais elegíveis;
- quantidade máxima;
- tamanho do chunk;
- descrição e justificativa.

Exemplo: “NF-es autorizadas emitidas antes de 01/01/2024, no máximo 100.000 documentos, chunks de 1.000”.

### 8.2 Seleção e enqueue atômicos

Para cada chunk:

```text
BEGIN TRANSACTION
    selecionar até N NF-es elegíveis ainda não controladas
    para cada NF-e:
        calcular OBJECT_KEY determinística
        INSERT NFE_MIGRATION_ITEM(status = QUEUED)
        ENQUEUE {controlId, nfeId, batchId, version}
        registrar AQ_MSGID
COMMIT
```

Se houver rollback, nem o item nem a mensagem ficam visíveis. Isso evita o dual-write entre tabela de controle e AQ.

Exemplo de cursor conceitual:

```sql
SELECT n.nfe_id,
       n.chave_nfe,
       n.data_emissao
  FROM poc_nfe_document n
 WHERE n.data_emissao < :cutoff_date
   AND n.situacao = 'AUTORIZADA'
   AND n.xml_clob IS NOT NULL
   AND NOT EXISTS (
       SELECT 1
         FROM nfe_migration_item i
        WHERE i.nfe_id = n.nfe_id
   )
 ORDER BY n.data_emissao, n.nfe_id
 FETCH FIRST :chunk_size ROWS ONLY;
```

O limite máximo do batch deve ser aplicado pelo pacote, não apenas pela interface. A restrição `UNIQUE (NFE_ID)` é a última barreira contra seleção duplicada.

### 8.3 Admission control

O job de seleção só admite novo chunk quando:

- `PIPELINE_PAUSED = 'N'`;
- o batch está em `SELECTING` ou `PROCESSING`;
- o batch ainda não atingiu `MAX_DOCUMENTS`;
- a quantidade de mensagens/itens em voo está abaixo de `MAX_INFLIGHT_MESSAGES`;
- não há sinal operacional de saturação.

Assim, selecionar 100 milhões de NF-es não exige enfileirar 100 milhões de mensagens de uma só vez.

---

## 9. Object key e idempotência

### 9.1 Convenção determinística

```text
nfe/<ano-emissao>/<mes-emissao>/<chave-nfe>.xml
```

Exemplo:

```text
nfe/2023/07/35230700000000000123550010000012341000012345.xml
```

A URI completa é derivada da configuração do ambiente:

```text
https://objectstorage.<regiao>.oraclecloud.com/n/<namespace>/b/<bucket>/o/<object-key>
```

Não incluir timestamp de tentativa, UUID aleatório ou número do worker na chave. A mesma NF-e sempre resolve para a mesma chave lógica.

### 9.2 Semântica após falha

O Object Storage não participa do commit Oracle. Portanto:

```text
PUT_OBJECT conclui
        |
worker cai antes do COMMIT
        |
AQ entrega novamente
        |
mesma NF-e -> mesma OBJECT_KEY
        |
worker verifica ou sobrescreve de forma controlada
        |
VERIFY -> COMMIT
```

Antes de sobrescrever um objeto existente, o worker deve confirmar que ele corresponde à mesma identidade. Se tamanho e hash já forem os esperados, pode tratar o upload como concluído. Se divergirem, deve marcar conflito, bloquear o item e não sobrescrever silenciosamente.

Para produção, recomenda-se habilitar versionamento, retenção ou regras de imutabilidade do bucket conforme a política corporativa. A PoC deve registrar `ETAG` e `OBJECT_VERSION_ID` quando essas informações estiverem disponíveis no método adotado.

---

## 10. Workers PL/SQL e DBMS_SCHEDULER

### 10.1 Pacotes

```text
PKG_NFE_SELECTION
  CREATE_BATCH
  SELECT_AND_ENQUEUE_CHUNK
  CLOSE_SELECTION

PKG_NFE_MIGRATION
  RUN_WORKER
  PROCESS_MESSAGE
  CLOB_TO_UTF8_BLOB
  PUT_OBJECT
  VERIFY_OBJECT

PKG_NFE_RECONCILIATION
  RECONCILE_ITEM
  RECONCILE_BATCH
  BUILD_BATCH_REPORT

PKG_NFE_EXCEPTION_MONITOR
  DRAIN_EXCEPTION_QUEUE
  MARK_EXCEPTION

PKG_NFE_PURGE_ADMIN
  APPROVE_BATCH
  REVOKE_APPROVAL_BEFORE_PURGE
  PURGE_BATCH_CHUNK
  CLOSE_PURGE
```

### 10.2 Conversão CLOB para BLOB UTF-8

`DBMS_CLOUD.PUT_OBJECT` recebe `BLOB` na sobrecarga usada pela PoC. Portanto, o worker converte explicitamente o XML em `CLOB` para bytes UTF-8:

```sql
PROCEDURE clob_to_utf8_blob(
    p_clob IN  CLOB,
    p_blob OUT BLOB
) IS
    l_dest_offset INTEGER := 1;
    l_src_offset  INTEGER := 1;
    l_lang_ctx    INTEGER := DBMS_LOB.DEFAULT_LANG_CTX;
    l_warning     INTEGER;
BEGIN
    DBMS_LOB.CREATETEMPORARY(p_blob, TRUE, DBMS_LOB.CALL);

    DBMS_LOB.CONVERTTOBLOB(
        dest_lob     => p_blob,
        src_clob     => p_clob,
        amount       => DBMS_LOB.LOBMAXSIZE,
        dest_offset  => l_dest_offset,
        src_offset   => l_src_offset,
        blob_csid    => NLS_CHARSET_ID('AL32UTF8'),
        lang_context => l_lang_ctx,
        warning      => l_warning
    );

    IF l_warning <> DBMS_LOB.NO_WARNING THEN
        RAISE_APPLICATION_ERROR(-20001, 'Aviso na conversao CLOB para UTF-8');
    END IF;
END;
```

O `BLOB` temporário deve ser liberado no bloco de sucesso e no tratamento de exceção.

### 10.3 Upload

```sql
DBMS_CLOUD.PUT_OBJECT(
    credential_name => 'NFE_OBJECT_STORAGE_CRED',
    object_uri      => l_object_uri,
    contents        => l_utf8_blob
);
```

O nome da credencial e o endpoint não devem estar hard-coded no pacote; devem ser resolvidos por configuração protegida. Segredos não devem ser gravados em logs ou tabelas de auditoria.

### 10.4 Algoritmo do worker

```text
1. Verificar pausa global e janela operacional.
2. Dequeue de uma mensagem com espera limitada.
3. Validar versão e campos do payload.
4. Carregar NFE_MIGRATION_ITEM e POC_NFE_DOCUMENT.
5. Se já VERIFIED:
      validar invariantes e fazer commit do dequeue.
6. Marcar UPLOADING na transação corrente.
7. Converter CLOB para BLOB UTF-8.
8. Calcular tamanho e SHA-256 de origem.
9. Derivar novamente a object key e compará-la ao controle.
10. Executar PUT_OBJECT ou validar objeto idêntico já existente.
11. Marcar UPLOADED.
12. Recuperar o objeto para verificação forte na PoC.
13. Comparar tamanho e SHA-256.
14. Marcar VERIFIED e registrar auditoria.
15. COMMIT: persiste estado e conclui o dequeue.
16. Em erro transitório: registrar diagnóstico seguro e ROLLBACK.
17. Em conflito/integridade: bloquear o item para análise, sem purge.
```

Para preservar informação de erro quando a transação principal sofre rollback, uma rotina de logging autônoma pode registrar apenas diagnóstico operacional, sem alterar o estado de negócio nem confirmar o dequeue. Seu uso deve ser pequeno e cuidadosamente testado para evitar contenção.

### 10.5 Jobs do Scheduler

Exemplo conceitual de quatro workers recorrentes:

```sql
BEGIN
    FOR i IN 1 .. 4 LOOP
        DBMS_SCHEDULER.CREATE_JOB(
            job_name        => 'NFE_UPLOAD_WORKER_' || TO_CHAR(i),
            job_type        => 'STORED_PROCEDURE',
            job_action      => 'PKG_NFE_MIGRATION.RUN_WORKER',
            start_date      => SYSTIMESTAMP,
            repeat_interval => 'FREQ=MINUTELY;INTERVAL=1',
            enabled         => FALSE,
            auto_drop       => FALSE,
            comments        => 'Worker PL/SQL para migracao historica de NFe'
        );
    END LOOP;
END;
/
```

Os jobs devem ser habilitados somente após credential, conectividade, ACLs, fila, tabelas, alertas e limites terem sido validados. Cada execução deve ter duração máxima e sair após período ocioso, permitindo manutenção e redistribuição natural nas execuções seguintes.

---

## 11. Retry, max_retries e exception queue

### 11.1 Categorias de erro

| Categoria | Exemplo | Ação |
|---|---|---|
| Transitório | timeout, indisponibilidade temporária, throttling | rollback; retry pela AQ |
| Permanente de configuração | credential inválida, ACL ausente, URI inválida | pausar pipeline e alertar |
| Integridade | hash/tamanho divergente, chave em conflito | não sobrescrever; `FAILED`/bloqueio |
| Dado inválido | CLOB nulo, encoding inválido, payload inválido | falha controlada e análise |
| Retry excedido | repetição além de `MAX_RETRIES` | exception queue e `EXCEPTION` |

### 11.2 Fluxo

```text
AQ -> DEQUEUE -> PUT/VERIFY
                    |
          +---------+---------+
          |                   |
        sucesso              erro
          |                   |
        COMMIT              ROLLBACK
                              |
                         nova tentativa
                              |
                     MAX_RETRIES excedido
                              |
                              v
                    NFE_MIGRATION_EX_Q
                              |
                    monitor + alerta + audit
                              |
                              v
                         EXCEPTION
```

O monitor da exception queue não deverá apagar a evidência antes de correlacioná-la e registrá-la. O reprocessamento de uma mensagem em `EXCEPTION` exigirá ação operacional explícita, correção da causa e nova mensagem referenciando o mesmo `CONTROL_ID` e a mesma `OBJECT_KEY`.

`BUSINESS_ATTEMPTS` é uma métrica de aplicação; o contador autoritativo de tentativas de entrega permanece na AQ. Eles não devem ser forçados a ter exatamente a mesma semântica.

---

## 12. Backpressure e throttling

A solução terá controles independentes em quatro níveis:

1. **Seleção:** `MAX_DOCUMENTS` limita o batch.
2. **Admissão:** `SELECTION_CHUNK_SIZE` e `MAX_INFLIGHT_MESSAGES` limitam o backlog ativo.
3. **Consumo:** quantidade de jobs workers e tempo máximo de execução.
4. **AQ:** número de shards e, após benchmark, `CQ_DEQ_FLOWCONTROL`.

Sinais para reduzir vazão ou pausar:

- crescimento contínuo do backlog;
- aumento de latência do `PUT_OBJECT`;
- respostas de throttling;
- aumento de rollback/retry;
- saturação de CPU, I/O, undo, redo ou sessões do Oracle;
- pressão no Streams Pool;
- aumento da exception queue;
- divergências de reconciliação.

Política inicial sugerida para a PoC:

- 1.000 itens por chunk de seleção;
- no máximo 10.000 itens em voo;
- 2 workers no primeiro teste, aumentando para 4 e 8;
- uma mensagem por dequeue na primeira versão;
- pausa automática de admissão diante de erro sistêmico, sem purge;
- ajuste somente após medir p50/p95/p99, throughput, recursos do banco e erros do Object Storage.

A pausa de admissão não precisa interromper instantaneamente transações já em andamento. Workers devem consultar a flag entre mensagens e encerrar de forma limpa.

---

## 13. Estados e transições

### 13.1 Estado por item

```text
QUEUED
   |
   v
UPLOADING ----erro transitório----> ROLLBACK/AQ retry
   |
   v
UPLOADED
   |
   v
VERIFYING
   |
   +----divergência---------------> FAILED
   |
   v
VERIFIED
   |
   | somente após batch APPROVED_FOR_PURGE
   | e chamada do pacote segregado
   v
PURGED

MAX_RETRIES excedido -------------> EXCEPTION
```

### 13.2 Estado do batch

```text
CREATED -> SELECTING -> PROCESSING -> RECONCILING
                                      |          |
                                      | falha    | todos íntegros
                                      v          v
                                   BLOCKED   READY_FOR_APPROVAL
                                                   |
                                         aprovação humana explícita
                                                   |
                                                   v
                                         APPROVED_FOR_PURGE
                                                   |
                                          execução manual segregada
                                                   |
                                                   v
                                                PURGING
                                                   |
                                                   v
                                                PURGED
```

Regras obrigatórias:

- `READY_FOR_APPROVAL` exige seleção encerrada e reconciliação `PASSED`.
- `APPROVED_FOR_PURGE` exige `APPROVED_BY`, `APPROVED_AT`, comentário e referência da evidência.
- a aprovação é por batch; não existe aprovação implícita por item.
- qualquer divergência posterior invalida a elegibilidade e bloqueia o purge.
- `PURGED` exige que todos os itens elegíveis estejam `PURGED` e que a contagem tenha sido reconciliada novamente.

---

## 14. Verificação e reconciliação

### 14.1 Verificação forte por item na PoC

Após o upload:

1. recuperar o objeto com `DBMS_CLOUD.GET_OBJECT`;
2. medir `DBMS_LOB.GETLENGTH`;
3. calcular SHA-256 sobre os bytes recuperados;
4. comparar com tamanho e SHA-256 do `BLOB` UTF-8 de origem;
5. persistir os dois conjuntos de valores;
6. somente então marcar `VERIFIED`.

O custo de baixar novamente cada objeto é aceitável para validar integridade na PoC. Em produção, poderá ser estudada uma verificação otimizada, desde que forneça evidência equivalente e seja compatível com os metadados realmente retornados pelo serviço.

### 14.2 Reconciliação do batch

O batch só fica `READY_FOR_APPROVAL` quando:

- seleção foi formalmente encerrada;
- `TOTAL = VERIFIED` para todos os itens que compõem o batch;
- `FAILED_COUNT = 0`;
- `EXCEPTION_COUNT = 0`;
- `MISSING_OBJECT_COUNT = 0`;
- `SIZE_MISMATCH_COUNT = 0`;
- `HASH_MISMATCH_COUNT = 0`;
- soma de bytes de origem = soma de bytes de objetos;
- não há mensagens pendentes inesperadas para o batch;
- foi produzido um relatório imutável ou protegido, referenciado pelo batch.

### 14.3 Inconsistências a detectar

- controle sem objeto;
- objeto com tamanho diferente;
- objeto com hash diferente;
- item `VERIFIED` sem `VERIFIED_AT`;
- item `VERIFIED` cujo CLOB já esteja nulo antes de aprovação;
- item `PURGED` com CLOB ainda presente;
- CLOB nulo para item não purgado;
- mensagem na exception queue;
- item travado logicamente em estado intermediário;
- objeto órfão sob o prefixo reservado da PoC;
- contadores do batch divergentes dos itens.

Objetos órfãos não devem ser apagados automaticamente. Devem ser relatados e tratados por processo separado e aprovado.

---

## 15. Human gate e purge segregado

### 15.1 Princípio

Upload, retry, verificação e reconciliação podem ser automáticos. A remoção do XML original é uma operação destrutiva e exige decisão humana explícita.

Não haverá:

- transição automática de `VERIFIED` para purge;
- job recorrente que aprove batches;
- aprovação baseada apenas em passagem de tempo;
- permissão de `UPDATE XML_CLOB` para o usuário dos workers;
- purge acionado por mensagem AQ.

### 15.2 Checklist de aprovação

O aprovador deve revisar:

- código e critérios do batch;
- total selecionado, verificado, falho e em exceção;
- bytes de origem e destino;
- resultados de tamanho e SHA-256;
- lista de divergências, que deve estar vazia;
- relatório de objetos ausentes e órfãos;
- retenção mínima e requisitos fiscais;
- versão/retention policy do bucket;
- restauração amostral bem-sucedida;
- evidência de backup/recuperação conforme política;
- janela e plano de interrupção do purge.

### 15.3 Aprovação explícita

O procedimento de aprovação deverá:

- aceitar `BATCH_ID`, comentário e referência de evidência;
- usar a identidade autenticada da sessão para `APPROVED_BY`, sem confiar em texto livre fornecido pelo cliente;
- gravar `APPROVED_AT = SYSTIMESTAMP`;
- conferir novamente status e reconciliação;
- bloquear a linha do batch durante a transição;
- registrar evento append-only.

Exemplo de contrato:

```sql
PKG_NFE_PURGE_ADMIN.APPROVE_BATCH(
    p_batch_id              => :batch_id,
    p_approval_comment      => :comment,
    p_approval_evidence_ref => :evidence_ref
);
```

### 15.4 Purge manual em chunks

O purge deverá ser iniciado explicitamente por operador autorizado e processar chunks pequenos:

```sql
UPDATE poc_nfe_document n
   SET n.xml_clob = NULL
 WHERE n.nfe_id IN (
       SELECT i.nfe_id
         FROM nfe_migration_item i
         JOIN nfe_migration_batch b
           ON b.batch_id = i.batch_id
        WHERE i.batch_id = :batch_id
          AND i.status = 'VERIFIED'
          AND b.status = 'APPROVED_FOR_PURGE'
          AND b.approved_by IS NOT NULL
          AND b.approved_at IS NOT NULL
          AND ROWNUM <= :chunk_size
 );
```

Esse SQL é apenas ilustrativo. O pacote real deve bloquear e revalidar o batch, marcar itens de forma consistente, registrar auditoria, controlar concorrência e confirmar cada chunk. Se qualquer pré-condição deixar de valer, o purge deve parar.

Após o purge, nova reconciliação confirma:

- quantidade purgada;
- `XML_CLOB IS NULL` para os itens purgados;
- objetos ainda existentes e íntegros;
- trilha completa de aprovação e execução.

### 15.5 Segregação de schemas e privilégios

Modelo recomendado:

```text
NFE_OWNER
  possui POC_NFE_DOCUMENT e tabelas de controle

NFE_MIGRATION_RUNTIME
  EXECUTE em PKG_NFE_MIGRATION
  dequeue/enqueue estritamente necessários
  leitura do XML por view/package
  sem UPDATE em POC_NFE_DOCUMENT.XML_CLOB
  sem EXECUTE em PKG_NFE_PURGE_ADMIN

NFE_PURGE_ADMIN
  EXECUTE em PKG_NFE_PURGE_ADMIN
  concedido somente a papel administrativo controlado
  pacote definer-rights com UPDATE mínimo necessário

NFE_AUDITOR
  SELECT em batch, item, reconciliação e auditoria
  sem privilégios de mutação ou purge
```

Evitar conceder `UPDATE` amplo na tabela de NF-e. A remoção deve ocorrer somente pelo pacote de purge, com privilégios concedidos diretamente ao owner do pacote e auditados.

---

## 16. Observabilidade

### 16.1 Métricas mínimas

- itens selecionados, enfileirados, processando, verificados, falhos, em exceção e purgados;
- backlog e idade da mensagem mais antiga;
- taxa de enqueue e dequeue;
- throughput em documentos/s e MiB/s;
- latência p50, p95 e p99 de upload e verificação;
- retries por categoria de erro;
- profundidade da exception queue;
- bytes de origem e destino por batch;
- divergências de tamanho/hash;
- número de workers ativos e duração das execuções;
- utilização de CPU, I/O, undo, redo, sessões e Streams Pool;
- quantidade de batches aguardando aprovação e tempo nessa fase;
- progresso e erros do purge manual.

### 16.2 Fontes de observabilidade

- tabelas `NFE_MIGRATION_BATCH`, `NFE_MIGRATION_ITEM` e `NFE_MIGRATION_AUDIT`;
- `NFE_RECONCILIATION_RUN`;
- views de dicionário AQ disponíveis ao usuário administrativo;
- views `DBA_SCHEDULER_*`/`ALL_SCHEDULER_*` conforme privilégio;
- métricas do Oracle Database e do OCI Object Storage;
- logs de alerta sem XML, credenciais ou dados sensíveis.

### 16.3 Alertas sugeridos

- nenhum progresso com backlog por período configurável;
- retry rate acima do limite;
- qualquer mensagem na exception queue;
- qualquer falha de hash/tamanho;
- credencial ou conectividade inválida;
- item intermediário acima do SLA;
- crescimento anormal do Streams Pool/redo/undo;
- batch `READY_FOR_APPROVAL` alterado após reconciliação;
- tentativa de purge sem aprovação;
- divergência após purge.

---

## 17. Segurança

1. Aplicar menor privilégio a schemas, packages, fila, Scheduler e credenciais.
2. Armazenar credenciais pelo mecanismo suportado de `DBMS_CLOUD`; nunca em código ou tabela comum.
3. Restringir o bucket/prefixo ao necessário para a PoC.
4. Usar TLS e validar a configuração de conectividade/ACL/wallet exigida pelo ambiente.
5. Habilitar criptografia em repouso e políticas IAM adequadas no OCI.
6. Considerar versionamento, retenção e Object Storage retention rules conforme governança.
7. Não registrar XML completo, tokens, chaves privadas ou headers de autenticação.
8. Tratar chave de acesso, namespace, bucket e URIs conforme classificação interna.
9. Auditar criação de batch, mudanças de configuração, aprovação e purge.
10. Impedir que quem opera workers aprove ou execute purge, quando a segregação de funções exigir.
11. Validar retenção fiscal/legal antes de qualquer aprovação.
12. Revisar proteção contra SQL injection em parâmetros administrativos e usar tipos fortes.

---

## 18. Plano de execução da PoC

### Fase 1 — Descoberta e baseline

- confirmar RU exato do Oracle 19c;
- confirmar disponibilidade e instalação do `DBMS_CLOUD`;
- validar Sharded AQ e privilégios;
- levantar quantidade, volume, tamanhos e distribuição temporal dos XMLs;
- definir dataset representativo, por exemplo 10 mil a 100 mil NF-es;
- medir baseline de CPU, I/O, redo, undo e tempo de leitura do CLOB.

### Fase 2 — OCI e segurança

- criar bucket/prefixo da PoC;
- configurar IAM e credential;
- validar conectividade e TLS;
- decidir versionamento/retenção;
- executar upload e download manual controlado.

### Fase 3 — Banco e AQ

- criar tabelas, índices e constraints;
- criar fila principal e exception queue;
- configurar Streams Pool conforme sizing inicial;
- implementar packages e auditoria;
- criar jobs desabilitados.

### Fase 4 — Teste funcional mínimo

- 10 a 100 NF-es de tamanhos variados;
- confirmar conversão UTF-8;
- confirmar object key;
- upload, download, hash e tamanho;
- confirmar que XML original permanece no Oracle;
- testar retry após falha simulada.

### Fase 5 — Concorrência e backpressure

- executar com 1, 2, 4 e 8 workers;
- variar chunks e limite em voo;
- medir impactos;
- testar pausa e retomada;
- validar `CQ_DEQ_FLOWCONTROL` apenas se necessário.

### Fase 6 — Falhas e recuperação

- queda após dequeue;
- queda após `PUT_OBJECT` antes do commit;
- timeout do Object Storage;
- credential inválida;
- XML inválido/nulo;
- objeto preexistente idêntico;
- objeto preexistente divergente;
- `MAX_RETRIES` e exception queue;
- reinício do banco/job.

### Fase 7 — Reconciliação e aprovação

- produzir relatório do batch;
- validar todas as contagens e hashes;
- executar restauração amostral;
- levar batch a `READY_FOR_APPROVAL`;
- testar rejeição de aprovação com divergência;
- registrar aprovação humana válida.

### Fase 8 — Purge controlado

- usar batch pequeno e aprovado;
- executar purge manual em chunks;
- confirmar auditoria e segregação de privilégio;
- reconciliar novamente;
- demonstrar que worker não consegue executar purge.

---

## 19. Casos de teste essenciais

| Caso | Resultado esperado |
|---|---|
| Inserção de controle e enqueue com rollback | nem item nem mensagem visíveis |
| Inserção de controle e enqueue com commit | item `QUEUED` e mensagem disponível |
| Dois workers concorrentes | cada mensagem concluída logicamente uma vez |
| Falha antes do upload | rollback e retry |
| Falha após upload e antes do commit | retry usa a mesma object key |
| Objeto preexistente idêntico | verificação conclui sem duplicidade lógica |
| Objeto preexistente divergente | bloqueio; sem sobrescrita silenciosa |
| Hash remoto divergente | item não chega a `VERIFIED` |
| `MAX_RETRIES` excedido | mensagem na exception queue e alerta |
| Pausa global | não há nova admissão; workers encerram de forma limpa |
| Purge sem aprovação | rejeitado |
| Aprovação sem reconciliação `PASSED` | rejeitada |
| Aprovação válida | `APPROVED_BY` e `APPROVED_AT` gravados |
| Worker tenta alterar XML | privilégio negado |
| Purge aprovado em chunks | somente itens do batch aprovado têm CLOB zerado |
| Reconciliação pós-purge | CLOB ausente e objeto íntegro para todos os itens purgados |

---

## 20. Entregáveis

- documento de arquitetura e decisões;
- scripts DDL das tabelas e AQ;
- packages PL/SQL de seleção, migração, reconciliação, exceção e purge;
- jobs `DBMS_SCHEDULER` inicialmente desabilitados;
- scripts de concessão/revogação de privilégios;
- configuração documentada de credential, IAM e conectividade;
- massa e scripts de teste;
- dashboard/consultas operacionais;
- relatório de reconciliação por batch;
- evidências dos testes de falha, retry, exception queue e idempotência;
- evidência do human gate e da segregação de purge;
- relatório final com throughput, impacto no banco, limites e recomendações.

---

## 21. Riscos e mitigação

| Risco | Mitigação |
|---|---|
| `DBMS_CLOUD` indisponível ou diferente no RU/serviço alvo | validar no início; tratar como go/no-go técnico |
| Saturação do banco | ondas pequenas, limite em voo, poucos workers, métricas e pausa |
| Pressão no Streams Pool | payload pequeno, sizing e benchmark |
| Timeout após upload | chave determinística e verificação idempotente |
| Corrupção/conversão de encoding | conversão explícita UTF-8 e SHA-256 byte a byte |
| Objeto divergente já existente | não sobrescrever silenciosamente; bloquear e alertar |
| Retry infinito | `MAX_RETRIES`, exception queue e ação operacional |
| Purge prematuro | human gate, constraints, package e privilégios separados |
| Contagem inconsistente | reconciliação por batch antes e depois do purge |
| Falta de auditabilidade | tabela append-only e identidade autenticada |
| Dependência indevida de TxEventQ/Kafka | limitar desenho às APIs AQ/Sharded AQ documentadas no 19c |

---

## 22. Decisões para evolução posterior

Somente após a PoC deverão ser decididos:

- tamanho definitivo dos batches e chunks;
- quantidade de shards e workers por topologia;
- sizing do Streams Pool;
- estratégia de verificação otimizada para produção;
- retenção do CLOB após aprovação e antes do purge;
- integração com processo corporativo de change/approval;
- política de versionamento/imutabilidade do bucket;
- particionamento das tabelas de controle e auditoria;
- read path para aplicações que precisem recuperar XML migrado;
- tratamento futuro de novas NF-es, explicitamente fora desta implantação.

---

## 23. Referências oficiais do Oracle 19c

- [DBMS_AQADM — CREATE_SHARDED_QUEUE, CREATE_EXCEPTION_QUEUE e parâmetros de fila](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_AQADM.html)
- [Oracle Database Advanced Queuing — performance e escalabilidade de Sharded Queues](https://docs.oracle.com/en/database/oracle/oracle-database/19/adque/aq-performance-scalability.html)
- [DBMS_CLOUD — PUT_OBJECT e demais operações de Object Storage](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/dbms_cloud.html)
- [Oracle Scheduler — criação e administração de jobs](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/scheduling-jobs-with-oracle-scheduler.html)

> **Nota de implementação:** os exemplos são deliberadamente conceituais e compatíveis com o baseline 19c documentado. Eles devem ser validados no Release Update exato, no tipo de serviço Oracle utilizado e com os padrões de segurança, tablespaces e licenciamento do cliente antes da execução.

---

## 24. Conclusão

A PoC proposta mantém toda a orquestração principal no Oracle Database 19c: seleção histórica, controle transacional, AQ, workers PL/SQL, Scheduler, upload e verificação. A arquitetura usa a AQ para aquilo que ela resolve bem — distribuição, concorrência, retry e exception handling — e mantém o estado de negócio e a auditoria em tabelas explícitas.

O desenho não altera o fluxo de novos inserts, não transporta XML na fila e não depende de TxEventQ/Kafka. A idempotência é obtida por referência estável e object key determinística; a consistência é demonstrada por verificação forte e reconciliação.

Finalmente, a operação destrutiva fica fora do pipeline automático. Um batch somente pode ser purgado depois de estar integralmente verificado, reconciliado e aprovado por uma pessoa identificada. O package e os privilégios separados transformam essa aprovação em controle técnico efetivo, e não apenas em convenção operacional.
