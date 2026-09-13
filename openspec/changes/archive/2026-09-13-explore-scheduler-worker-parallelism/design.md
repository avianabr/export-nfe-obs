## Context

O runtime possui um job Scheduler desabilitado que chama `run_workers` e os
testes de escala criam jobs descartáveis. A proposta define os comportamentos
esperados; este documento explora uma orquestração permanente e controlada.

## Goals / Non-Goals

**Goals:**

- Transformar o paralelismo de teste em uma capacidade configurável, limitada e
  observável.
- Preservar transações AQ, redelivery e o estado seguro por padrão.

**Non-Goals:**

- Alterar TEQ, criar autoscaling por carga ou processar múltiplos batches sem
  política explícita.

## Decisions

### Um coordinator e jobs worker nomeados

Um coordinator de Scheduler cria ou habilita workers nomeados sob propriedade
de `NFE_OWNER`, até o limite configurado, e os desabilita ao concluir ou parar
o batch. Isso permite monitorar cada execução e evita depender de múltiplos
slaves implícitos de um único job. A alternativa de um job com múltiplos slaves
é mais simples, mas oferece menos identificação e controle por worker.

### Início manual por batch selecionado

O operador inicia o coordinator explicitamente para um batch elegível e
identificado. Não haverá job periódico que procure batches. Isso elimina seleção
automática, mantém a aprovação operacional no ponto de partida e preserva o
estado seguro por padrão.

### Limite persistido e snapshot por batch

O limite é validado na configuração e copiado para o batch ao iniciar. Mudanças
posteriores aplicam-se somente a batches futuros, evitando mudança de
concorrência no meio de uma execução. A alternativa de ler a configuração em
cada worker dificulta explicar a capacidade efetiva de um batch em andamento.

### Gate como autoridade de desligamento

Workers verificam o gate antes de buscar nova mensagem; rollback desabilita o
coordinator e impede novos trabalhos, sem remover mensagens. Jobs em execução
terminam a transação atual ou devolvem a mensagem pela semântica AQ.

### Métricas sem dados sensíveis

O dashboard usa metadados Scheduler, batch e item: workers ativos, último
heartbeat, contagens e erros resumidos. Não inclui XML, payload AQ, headers ou
credenciais.

## Risks / Trade-offs

- Concorrência maior pode esgotar sessões, CPU ou conexões Object Storage →
  impor máximo documentado e iniciar com limite conservador.
- Worker interrompido pode ficar em `WAIT` antes da redelivery → expor estado
  AQ e aguardar a política de retry antes de alertar.
- Jobs residuais após falha de coordinator → nomes determinísticos, limpeza
  idempotente e rollback que desabilita todos os jobs pertencentes ao runtime.

## Migration Plan

1. Adicionar configuração e controles de batch sem alterar o job atual.
2. Criar coordinator/workers desabilitados e dashboard de estado.
3. Validar em batch isolado com limites 1, 2 e 10; comparar throughput e
   redelivery.
4. Habilitar operacionalmente apenas após aprovação do runbook.
5. Rollback: desabilitar coordinator e workers, manter mensagens e evidências.

## Open Questions

- Qual máximo de workers é seguro para o PDB e a capacidade contratada de
  Object Storage?
