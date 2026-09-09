## Purpose

Define a seleção controlada de XMLs históricos de NF-e e sua admissão atômica no pipeline de migração, sem alterar o fluxo de criação de novas NF-es.

## ADDED Requirements

### Requirement: Seleção histórica configurável por batch
O sistema SHALL permitir criar batches de migração com data de corte, situações fiscais elegíveis, quantidade máxima, tamanho de chunk, justificativa e cópia auditável dos critérios. A seleção SHALL incluir somente NF-es históricas com XML de origem presente e que ainda não possuam item de migração.

#### Scenario: Seleção de documentos elegíveis
- **WHEN** um batch ativo solicita um chunk de seleção dentro de seu limite máximo
- **THEN** o sistema cria itens somente para NF-es que atendem aos critérios persistidos e registra sua associação ao batch

#### Scenario: Documento já controlado
- **WHEN** uma NF-e já possui item de migração
- **THEN** o sistema não a seleciona novamente para outro batch

### Requirement: Admissão atômica na fila TEQ por referência
O sistema SHALL criar cada item de controle e publicar sua solicitação de migração na Oracle Transactional Event Queue (TEQ) na mesma transação do banco. A mensagem SHALL conter somente a versão do contrato e referências pequenas suficientes para localizar o item, a NF-e e o batch; ela MUST NOT conter XML, CLOB ou BLOB.

#### Scenario: Commit do chunk de admissão
- **WHEN** a transação de um chunk é confirmada
- **THEN** os itens em estado `QUEUED` e as mensagens TEQ correspondentes tornam-se visíveis conjuntamente

#### Scenario: Rollback do chunk de admissão
- **WHEN** a transação de um chunk é desfeita antes da confirmação
- **THEN** nem os itens de controle nem as mensagens TEQ daquele chunk tornam-se visíveis

### Requirement: Limites de admissão e pausa operacional
O sistema SHALL interromper a admissão de novos itens quando o pipeline estiver pausado, o batch atingir sua quantidade máxima, o limite configurado de itens em voo for atingido ou o batch não estiver em fase elegível. A interrupção da admissão MUST NOT remover itens ou mensagens já confirmados.

#### Scenario: Backlog atinge o limite
- **WHEN** a quantidade de itens em voo alcança o limite configurado
- **THEN** o sistema não publica novo chunk até que a quantidade volte a ficar abaixo do limite

#### Scenario: Pausa global ativada
- **WHEN** a pausa global é ativada
- **THEN** o sistema não admite novas NF-es e preserva o backlog já existente para retomada posterior
