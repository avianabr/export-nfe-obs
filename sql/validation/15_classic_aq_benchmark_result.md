# Resultado do benchmark — AQ clássico

Executado em `PDB_POCRT_02` em 2026-09-09 com cohorts sintéticos isolados de
1.000 NF-es por rodada. Cada item fez upload e leitura de verificação no Object
Storage; não houve purge. A coleta usou `14_collect_classic_aq_benchmark.sql`.

| Workers | Batch | Verificados | Falhas | Exceções | Throughput (itens/s) | p50 (s) | p95 (s) | p99 (s) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 47 | 1000 | 0 | 0 | 5.26 | 121 | 183 | 188 |
| 2 | 48 | 1000 | 0 | 0 | 6.17 | 125 | 157 | 160 |
| 4 | 49 | 1000 | 0 | 0 | 9.62 | 81 | 101 | 102.01 |
| 8 | 50 | 1000 | 0 | 0 | 15.15 | 45 | 63 | 64.01 |

## Leitura

O throughput aumentou em todas as rodadas e a latência p95/p99 caiu até oito
workers. Esta é evidência de PoC, não um limite de produção: a decisão final
deve incluir os indicadores de CPU, I/O, redo, undo e Streams Pool aprovados
para o ambiente.

Após a coleta, execute o rollback operacional AQ clássico para retornar o gate
e o job ao estado desabilitado e compare novamente a preservação da TEQ.
