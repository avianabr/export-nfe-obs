# Resultado do batch representativo com purge controlado

## Evidência executada

Em 2026-09-08, foi executado no ambiente de PoC um batch sintético de um único
documento, usando exclusivamente a chave de teste reservada `000020260904`.

| Evidência | Resultado |
| --- | --- |
| Batch | `BATCH_ID = 28` |
| Item de controle | `CONTROL_ID = 100` |
| Admissão | `ADMITTED_COUNT = 1` |
| Transferência e reconciliação inicial | item `VERIFIED`; batch `READY_FOR_APPROVAL` com reconciliação `PASSED` |
| Aprovação humana | `NFE_PURGE_ADMIN`, em 2026-09-08 18:05:40 GMT |
| Purge manual | `PURGED_COUNT = 1` |
| Reconciliação pós-purge | passou; objeto, ausência de conteúdo de origem, contagens e auditoria confirmados |
| Restauração amostral | passou; objeto reconstruído em CLOB temporário e comparado à evidência de tamanho/SHA-256 |

O teste de restauração não repovoou a linha fiscal de origem. Recuperação para
a fonte é uma operação separada, explicitamente autorizada, fora do fluxo de
purge da PoC.

## Parâmetros e limites recomendados para a PoC

- Iniciar com `WORKER_COUNT = 2` e `MAX_INFLIGHT_MESSAGES = 100`; o benchmark
  prévio mostrou o melhor equilíbrio nessa configuração.
- Usar chunks pequenos e incrementais, começando por 1 a 100 documentos
  sintéticos, e manter jobs desabilitados até uma autorização operacional
  explícita.
- Manter a pausa global como mecanismo de contenção; qualquer exceção,
  divergência de integridade ou backlog sem progresso exige investigação antes
  de nova admissão.
- Não ampliar para documentos fiscais reais enquanto retenção/versionamento do
  bucket, permissões segregadas, restauração autorizada e métricas de CPU/I/O,
  redo, undo e Streams Pool forem aceitos pelos responsáveis.

## Critérios para expansão

1. A matriz de falhas e privilégios deve ter evidência publicada e revisada.
2. A reconciliação deve permanecer `PASSED` em batches representativos, sem
   itens `FAILED` ou `EXCEPTION`.
3. A aprovação deve ser registrada pela identidade administrativa apropriada e
   cada purge deve ocorrer em chunks manualmente iniciados.
4. Cada batch purgado deve concluir reconciliação pós-purge e uma leitura de
   restauração amostral antes de qualquer aumento de escala.
