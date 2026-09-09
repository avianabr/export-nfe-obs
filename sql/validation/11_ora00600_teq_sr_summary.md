# Resumo para SR Oracle — ORA-00600 em TEQ dequeue

## Incidente identificado

- Assinatura: `ORA-00600 [kwsdRmtDqIpc: error in ipc send] [24039]`
- Horário: `2026-09-08 18:31:04.664 GMT`
- PDB: `PDB_POCRT_02`
- Instância: `pocrt1` (host `dev11-htoeb`)
- ADR incident: `836580`
- Componente sinalizador: `AQ`
- Problem key: `ORA 600 [kwsdRmtDqIpc: error in ipc send]`
- Trace indicado pelo alert log:
  `/u02/app/oracle/diag/rdbms/pocrt/pocrt1/trace/pocrt1_ora_303734.trc`
- Arquivo específico do incidente:
  `/u02/app/oracle/diag/rdbms/pocrt/pocrt1/incident/incdir_836580/pocrt1_ora_303734_i836580.trc`

## Ambiente

- Oracle AI Database 26ai EE Extreme Performance `23.26.3.0.0`
- RU: `23.26.3.0.0`, patch `39578879`, aplicado com sucesso em 2026-07-07
- Banco primário, `READ WRITE`, `ARCHIVELOG`, `FORCE_LOGGING=YES`
- Fila normal: `NFE_OWNER.NFE_MIGRATION_Q`, `MAX_RETRIES=3`, enqueue/dequeue
  habilitados
- Exception queue: `NFE_OWNER.NFE_MIGRATION_EX_Q`, habilitada

## Passos mínimos observados

1. Um envelope TEQ RAW de referência pequena é enfileirado e confirmado.
2. `NFE_OWNER.PKG_NFE_WORKER.PROCESS_ONE` inicia o `DBMS_AQ.DEQUEUE` da
   mensagem de teste de redelivery transitório.
3. O `DBMS_AQ.DEQUEUE` falha com a assinatura acima, antes da simulação de
   timeout transitório e antes de qualquer confirmação de sucesso do item.

O fluxo normal anterior processou o item representativo do batch 28 até
`VERIFIED`; a falha observada é específica ao caminho AQ/TEQ de teste de
redelivery e não foi atribuída ao upload ou ao purge.

## Estado observado após o incidente

- `NFE_MIGRATION_Q`: 95 mensagens `PROCESSED`, 3 `READY`, 6 `RETRYEXPIRED`.
- Artefatos `RETRY-*` de testes anteriores foram preservados como evidência;
  não executar limpeza adicional até a orientação do DBA/Oracle Support.
- Após restaurar `PKG_NFE_WORKER` ao dequeue normal, duas chamadas separadas a
  `PROCESS_ONE(false)` retornaram `ORA-25228` no `DBMS_AQ.DEQUEUE`, apesar de a
  visão `AQ$NFE_MIGRATION_Q` listar três mensagens `READY`. Isso impede tanto
  o consumo do backlog quanto a simulação segura de novos batches.

## Solicitação ao Oracle Support

1. Identificar causa conhecida/correção para `kwsdRmtDqIpc` com argumento
   `24039` na RU `23.26.3.0.0` ao fazer dequeue TEQ.
2. Informar workaround suportado e se há patch/RU recomendado.
3. Confirmar se os estados `READY`/`RETRYEXPIRED` e os artefatos de teste
   devem ser preservados ou tratados antes de retomar os testes de redelivery.
4. Explicar por que mensagens `READY` não são elegíveis ao dequeue normal e
   indicar a ação suportada para restabelecer o consumo TEQ.

## Anexos requeridos

- Saída de `10_collect_ora00600_teq_evidence.sql`.
- Trace `pocrt1_ora_303734.trc` e o pacote IPS/ADR do incidente `836580`.
- Horário UTC, versão/RU, configuração de fila e este resumo.

Não anexar payloads TEQ, XMLs, credenciais ou headers de autenticação.
