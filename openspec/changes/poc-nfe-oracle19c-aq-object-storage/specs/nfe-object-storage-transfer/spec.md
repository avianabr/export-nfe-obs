## Purpose

Define a transferência idempotente e verificável dos XMLs históricos de NF-e para o OCI Object Storage a partir de solicitações entregues pela Oracle Transactional Event Queue.

## ADDED Requirements

### Requirement: Transferência por referência com conteúdo UTF-8
O sistema SHALL processar uma solicitação TEQ carregando o XML da NF-e referenciada no catálogo Oracle, convertendo seu CLOB em bytes UTF-8 e enviando esses bytes ao OCI Object Storage. O destino SHALL ser derivado de uma chave determinística baseada na identidade da NF-e e na sua data de emissão.

#### Scenario: Transferência de uma solicitação válida
- **WHEN** um worker recebe uma solicitação TEQ válida para um item em migração
- **THEN** o sistema envia ao Object Storage a representação UTF-8 do XML para a chave determinística do item

#### Scenario: Payload inválido ou versão não suportada
- **WHEN** um worker recebe uma solicitação sem referências obrigatórias ou com versão de contrato não suportada
- **THEN** o sistema não marca o item como verificado e registra o diagnóstico para tratamento operacional

### Requirement: Idempotência após entrega repetida
O sistema SHALL tratar entregas repetidas da mesma solicitação sem criar objetos logicamente distintos. Quando o objeto já existir com tamanho e SHA-256 iguais aos bytes de origem, o sistema SHALL concluir a migração usando esse objeto; quando a identidade ou a integridade divergir, MUST bloquear o item sem sobrescrever silenciosamente o objeto.

#### Scenario: Nova entrega após upload sem confirmação Oracle
- **WHEN** uma solicitação é entregue novamente após o objeto ter sido gravado antes da confirmação da transação Oracle
- **THEN** o sistema reutiliza a mesma chave e conclui somente após validar que o objeto corresponde aos bytes de origem

#### Scenario: Objeto preexistente divergente
- **WHEN** a chave determinística já referencia um objeto com tamanho ou SHA-256 diferente do XML de origem
- **THEN** o sistema marca o item como falho ou bloqueado para análise e não o substitui automaticamente

### Requirement: Verificação forte antes do estado verificado
O sistema SHALL recuperar o objeto gravado e comparar seu tamanho e SHA-256 com os bytes UTF-8 de origem antes de marcar o item como `VERIFIED`. O sistema SHALL persistir a evidência de tamanho, hash e identificadores disponíveis do objeto no item de migração.

#### Scenario: Verificação íntegra
- **WHEN** o objeto recuperado possui o mesmo tamanho e SHA-256 dos bytes de origem
- **THEN** o item é marcado como `VERIFIED` e a evidência de integridade é registrada

#### Scenario: Divergência de integridade
- **WHEN** o tamanho ou SHA-256 do objeto recuperado diverge da origem
- **THEN** o item não alcança o estado `VERIFIED` e a divergência fica disponível para reconciliação e alerta

### Requirement: Confirmação coordenada do processamento
O sistema SHALL confirmar a remoção da mensagem TEQ somente junto com o estado final de sucesso do item. Para falhas transitórias, SHALL desfazer o processamento para que a TEQ possa redeliver a solicitação conforme sua política de tentativas.

#### Scenario: Sucesso de upload e verificação
- **WHEN** upload e verificação terminam com sucesso
- **THEN** a confirmação persiste o estado `VERIFIED` e conclui o consumo da mensagem

#### Scenario: Falha transitória durante a transferência
- **WHEN** ocorre timeout, indisponibilidade temporária ou throttling antes da confirmação
- **THEN** o estado final de sucesso não é persistido e a solicitação permanece elegível para nova entrega pela TEQ
