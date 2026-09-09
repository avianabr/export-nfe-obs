# nfe-classic-aq-transport Specification

## Purpose
Definir um transporte AQ clássico compartilhado e verificável para a PoC de
migração de NF-e, compatível com APIs Oracle 19c e isolado da TEQ investigada.

## Requirements

### Requirement: Transporte AQ clássico compartilhado compatível com 19c
O sistema SHALL usar uma fila AQ clássica persistente, de consumidor único e
payload RAW para o transporte alternativo da PoC. A implantação MUST usar
somente APIs e atributos suportados pelo Oracle 19c, sem criar TxEventQ ou AQ
sharded queue como parte desse transporte.

#### Scenario: Go/no-go de compatibilidade
- **WHEN** a implantação alternativa é validada na RU alvo
- **THEN** a evidência identifica a queue table, a fila normal, a exception
  queue, o payload RAW e as APIs AQ clássicas utilizadas antes de admitir NF-es

### Requirement: Admissão atômica em AQ clássico por referência
O sistema SHALL inserir o item de migração e enfileirar, na mesma transação
Oracle, um envelope RAW UTF-8 contendo somente a versão do contrato e as
referências `controlId`, `nfeId` e `batchId`. O envelope MUST NOT conter XML,
CLOB, BLOB, credenciais ou cabeçalhos de autenticação.

#### Scenario: Commit e rollback de admissão
- **WHEN** um chunk é confirmado ou desfeito
- **THEN** o item `QUEUED` e sua mensagem AQ clássica tornam-se visíveis juntos
ou não se tornam visíveis, respectivamente

### Requirement: Consumo transacional e redelivery confiável
O worker SHALL remover uma mensagem AQ clássica somente no mesmo commit que
persiste o sucesso verificado do item. Uma falha transitória MUST desfazer o
trabalho para permitir redelivery conforme a política da fila; mensagens que
excedam essa política SHALL ser encaminhadas à exception queue e correlacionadas
ao item para intervenção operacional.

#### Scenario: Falha transitória antes da confirmação
- **WHEN** ocorre falha transitória após a entrega da mensagem e antes do
  commit de sucesso
- **THEN** o item não alcança `VERIFIED` e a mensagem permanece elegível para
  redelivery sem reconhecimento prematuro

#### Scenario: Exceção após retries esgotados
- **WHEN** uma mensagem excede o máximo de retries configurado
- **THEN** a exception queue preserva a correlação e o item é exposto como
  `EXCEPTION` sem remover ou alterar o XML de origem

### Requirement: Coexistência e reversibilidade do transporte
O transporte AQ clássico SHALL usar identificadores e controles independentes
da TEQ investigada. A implantação MUST NOT apagar, consumir ou alterar mensagens
TEQ, incidentes ADR ou evidências do chamado Oracle sem autorização explícita.

#### Scenario: Ativação do transporte alternativo
- **WHEN** o modo AQ clássico é ativado para um batch de PoC
- **THEN** somente mensagens AQ clássicas desse batch são admitidas e processadas
e os artefatos TEQ permanecem disponíveis para diagnóstico
