# Roteiro de benchmark da PoC

Execute como `NFE_OWNER`. Não habilite os jobs recorrentes e não execute purge.

## Preparação de cada rodada

1. Escolha um limite de itens igual para todas as rodadas, por exemplo 20.
2. Crie um batch novo com `PKG_NFE_SELECTION.CREATE_BATCH`, com corte e situações que retornem documentos sintéticos ainda não controlados.
3. Admita exatamente o mesmo número de itens com `PKG_NFE_MIGRATION.ADMIT_CHUNK` e confirme a transação.
4. Registre os valores iniciais de `V$SYSSTAT`, `V$SYSMETRIC`, `V$UNDOSTAT`, Streams Pool, `V_NFE_MIGRATION_DASHBOARD` e `V_NFE_MIGRATION_THROUGHPUT`.

## Rodadas

Repita para 1, 2, 4 e 8 workers, mantendo o mesmo `MAX_INFLIGHT_MESSAGES` e tamanho de batch.

```sql
@sql/validation/04_benchmark_nfe_pipeline.sql
-- informe o worker_count da rodada e o mesmo inflight_limit

begin
  pkg_nfe_scheduler.run_workers;
end;
/

select * from v_nfe_migration_dashboard order by batch_id;
select * from v_nfe_migration_throughput order by metric_hour desc;
```

Se houver backlog remanescente, execute `RUN_WORKERS` novamente até não haver mensagens correlacionadas do batch. Não misture batches entre rodadas.

## Coleta final e registro

Para cada rodada, registre:

- workers, inflight limit, tamanho do batch e duração total;
- documentos/bytes verificados e throughput;
- latência por item (`VERIFIED_AT - ENQUEUED_AT`), calculando p50/p95/p99;
- deltas de CPU, I/O físico, redo, undo e Streams Pool;
- backlog, falhas, exception queue e divergências.

```sql
select percentile_cont(0.50) within group (order by latency_seconds) p50,
       percentile_cont(0.95) within group (order by latency_seconds) p95,
       percentile_cont(0.99) within group (order by latency_seconds) p99
from (
  select (cast(verified_at as date)-cast(enqueued_at as date))*86400 latency_seconds
  from nfe_migration_item
  where batch_id = :batch_id and status = 'VERIFIED'
);
```

Aceite uma configuração somente se não houver falhas/divergências, a pressão de banco permanecer dentro dos limites aprovados e a latência/throughput forem melhores ou equivalentes à configuração anterior.
