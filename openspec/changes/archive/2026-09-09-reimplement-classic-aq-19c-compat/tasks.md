## 1. Descoberta e isolamento da TEQ

- [x] 1.1 Registrar snapshot final de ADR, filas TEQ, mensagens e grants antes da mudança; verificar que os artefatos do incidente 836580 permanecem inalterados
- [x] 1.2 Validar na RU 23.26.3.0.0 as APIs `DBMS_AQ`/`DBMS_AQADM`, atributos de queue table e política de retry compatíveis com 19c; registrar go/no-go sem criar TxEventQ ou AQ sharded queue
- [x] 1.3 Definir nomes separados para queue table, fila normal e exception queue AQ clássicas; verificar que não colidem com nenhum objeto `NFE_MIGRATION_Q`/`NFE_MIGRATION_EX_Q`

## 2. Transporte AQ clássico e segurança

- [x] 2.1 Criar queue table AQ clássica persistente, fila RAW de consumidor único e exception queue com política inicial de retries; verificar enqueue/dequeue de envelope de referência e encaminhamento para exceção
- [x] 2.2 Criar grants AQ mínimos para owner, runtime, monitor e auditor sem ampliar privilégios de `XML_CLOB` ou purge; verificar as negações com a sessão runtime
- [x] 2.3 Adicionar seleção de transporte auditável e desabilitada por padrão para batches/runs; verificar que nenhum batch novo usa AQ clássico antes da habilitação explícita

## 3. Admissão e worker por AQ clássico

- [x] 3.1 Implementar enqueue AQ clássico na mesma transação de criação do item, mantendo o envelope RAW UTF-8 somente com referências; verificar commit/rollback atômicos de item e mensagem
- [x] 3.2 Implementar dequeue `REMOVE`/`ON_COMMIT` AQ clássico no worker e carregamento seguro do item; verificar que sucesso `VERIFIED` e remoção da mensagem persistem juntos
- [x] 3.3 Implementar rollback para timeout/throttling transitório e redelivery AQ clássico; verificar que a mensagem permanece elegível e o item não recebe sucesso prematuro
- [x] 3.4 Implementar monitor da exception queue AQ clássica com correlação e diagnóstico seguro; verificar item `EXCEPTION` após exceder o máximo de retries

## 4. Operação e coexistência

- [x] 4.1 Adaptar jobs `DBMS_SCHEDULER`, pausa, limites de inflight e workers para o modo AQ clássico; verificar execução limitada e que jobs TEQ permanecem desabilitados/inalterados
- [x] 4.2 Adaptar dashboard, auditoria e reconciliação para expor modo de transporte, backlog, retries e exceções AQ clássicas; verificar visibilidade sem XML ou credenciais
- [x] 4.3 Implementar rollback operacional que desabilita AQ clássico sem tocar TEQ, ADR ou mensagens preexistentes; verificar por snapshot comparativo dos objetos e contagens TEQ

## 5. Validação da PoC

- [x] 5.1 Executar matriz AQ clássica de concorrência, rollback, redelivery, objeto idêntico/divergente, exception queue, pausa/retomada e negação de privilégios; publicar evidências da RU alvo
- [x] 5.2 Executar batch sintético isolado ponta a ponta pelo modo AQ clássico, até `READY_FOR_APPROVAL`, sem purge; verificar objetos, hashes, reconciliação e preservação de toda evidência TEQ
- [x] 5.3 Benchmarkar 1, 2, 4 e 8 workers AQ clássicos com limites de inflight controlados; registrar p50/p95/p99, throughput e impacto no banco para decisão de continuidade
