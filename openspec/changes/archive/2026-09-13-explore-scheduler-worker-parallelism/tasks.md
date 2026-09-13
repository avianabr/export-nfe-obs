## 1. Modelo e controles de paralelismo

- [x] 1.1 Definir o limite inicial e o máximo suportado de workers com benchmark no PDB e Object Storage; verificar documentação de capacidade e registrar a decisão operacional.
- [x] 1.2 Estender os controles de configuração e batch para persistir o limite e seu snapshot; verificar que valores inválidos não habilitam jobs ou selecionam batch.
- [x] 1.3 Implementar o coordinator iniciado manualmente para um batch elegível; verificar que ele não seleciona batches automaticamente e cria no máximo o limite de workers nomeados.

## 2. Runtime e recuperação

- [x] 2.1 Implementar workers Scheduler idempotentes, associados ao batch, com gate antes de novo dequeue; verificar processamento paralelo sem exceder o limite.
- [x] 2.2 Implementar parada e rollback do coordinator/workers; verificar que mensagens AQ permanecem em `WAIT` ou `READY` para redelivery e nenhum item não verificado alcança `VERIFIED`.
- [x] 2.3 Implementar limpeza de jobs residuais por nome e batch; verificar que repetição após falha não cria jobs duplicados.

## 3. Observabilidade e operação

- [x] 3.1 Expor no dashboard o limite, workers ativos, progresso do batch e falhas resumidas; verificar que não são exibidos XML, payload AQ, headers ou credenciais.
- [x] 3.2 Atualizar runbook para início manual, acompanhamento, parada e rollback; verificar que instalação continua com coordinator e workers desabilitados por padrão.

## 4. Validação de escala

- [x] 4.1 Executar batches isolados com 1, 2, 5 e 10 workers; verificar throughput, contagens, integridade e isolamento de TEQ em cada execução.
- [x] 4.2 Simular falha de um worker durante batch paralelo; verificar redelivery/exceção isolada e continuidade dos demais workers dentro do limite.
- [x] 4.3 Executar `openspec validate explore-scheduler-worker-parallelism --strict` e `git diff --check`; verificar que ambos terminam sem erro.
