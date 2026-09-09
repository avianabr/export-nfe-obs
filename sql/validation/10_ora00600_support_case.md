# Evidências para chamado Oracle: ORA-00600 em dequeue TEQ

## Sintoma

Durante a execução de `PKG_NFE_WORKER.PROCESS_ONE` no teste de redelivery
transitório, a chamada `DBMS_AQ.DEQUEUE` retornou:

```text
ORA-00600: internal error code, arguments:
[kwsdRmtDqIpc: error in ipc send], [24039]
```

O erro ocorreu antes da simulação de falha transitória. Portanto, não foi
causado pelo rollback após upload; ocorreu na entrega AQ/TEQ da mensagem de
teste.

## Coleta necessária

1. Como `SYS` no PDB afetado, executar
   `sql/validation/10_collect_ora00600_teq_evidence.sql` e preservar o arquivo
   `.log` gerado pelo SQL*Plus.
2. Como usuário do software Oracle no host do banco, usar ADRCI/IPS ou AHF para
   empacotar o incidente `ORA-00600` correspondente, incluindo `alert.log` e o
   trace apontado pelo incidente.
3. Registrar a hora UTC exata, PDB, instância/RAC node, versão completa e RU
   retornados pela coleta.

## Dados a incluir no SR

- Assinatura completa: `ORA-00600 [kwsdRmtDqIpc: error in ipc send] [24039]`.
- Arquivo de coleta SQL e pacote IPS/ADR do incidente.
- Configuração da fila `NFE_MIGRATION_Q` e estado das mensagens, sem payloads.
- Estado/DDL time de `PKG_NFE_WORKER` e o fato de que o erro veio de
  `DBMS_AQ.DEQUEUE`.
- Passos mínimos de reprodução: enqueue de envelope RAW pequeno, commit, e
  dequeue do item de teste no PDB afetado.

Não anexar XMLs de NF-e, payloads de mensagens, credenciais, headers de
autenticação ou segredos de Object Storage.
