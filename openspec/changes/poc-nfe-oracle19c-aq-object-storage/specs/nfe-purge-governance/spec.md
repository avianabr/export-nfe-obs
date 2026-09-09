## Purpose

Define o controle humano e a segregação técnica que protegem os XMLs de origem contra purge prematuro após sua migração ao Object Storage.

## ADDED Requirements

### Requirement: Aprovação humana explícita por batch
O sistema SHALL aceitar aprovação de purge somente para batch com reconciliação aprovada e estado `READY_FOR_APPROVAL`. A aprovação SHALL registrar a identidade autenticada do aprovador, data e hora, comentário e referência de evidência, e SHALL mover o batch para `APPROVED_FOR_PURGE` apenas após revalidar suas pré-condições.

#### Scenario: Aprovação válida
- **WHEN** um usuário autorizado aprova um batch integralmente reconciliado com comentário e evidência
- **THEN** o sistema grava aprovador e momento autenticados, registra auditoria e habilita o batch para purge manual

#### Scenario: Tentativa de aprovação sem reconciliação
- **WHEN** um usuário tenta aprovar batch sem reconciliação aprovada ou com divergências
- **THEN** o sistema rejeita a aprovação e mantém o XML de origem intacto

### Requirement: Purge manual limitado a batch aprovado
O sistema SHALL permitir purge somente por ação administrativa explícita, em chunks limitados, para itens `VERIFIED` de batch `APPROVED_FOR_PURGE`. Antes de cada chunk, SHALL revalidar a aprovação e registrar o resultado de cada alteração; nenhuma operação automática de upload, verificação ou reconciliação poderá iniciar purge.

#### Scenario: Purge de batch aprovado
- **WHEN** um administrador autorizado inicia purge para batch aprovado
- **THEN** o sistema remove somente o conteúdo XML dos itens verificados daquele batch, preserva a linha fiscal e registra a transição para `PURGED`

#### Scenario: Tentativa de purge sem aprovação
- **WHEN** é solicitada a remoção de XML para batch não aprovado ou item não verificado
- **THEN** o sistema rejeita a operação sem alterar o CLOB de origem

### Requirement: Segregação efetiva de privilégios
O sistema SHALL separar a identidade e os privilégios usados por workers de migração daqueles usados para aprovação e purge. A identidade de execução dos workers MUST NOT possuir permissão para alterar a coluna de XML de origem nem executar a operação administrativa de purge.

#### Scenario: Worker tenta remover XML de origem
- **WHEN** a identidade de um worker tenta atualizar o XML de uma NF-e
- **THEN** o banco nega a operação e a tentativa pode ser auditada

### Requirement: Reconciliação posterior ao purge
O sistema SHALL executar ou exigir uma reconciliação posterior ao purge que confirme, para cada item purgado, a ausência do CLOB de origem, a permanência íntegra do objeto e a consistência das contagens e da trilha de aprovação.

#### Scenario: Conclusão do purge
- **WHEN** todos os chunks de purge terminam
- **THEN** o batch só é marcado como `PURGED` após a reconciliação posterior confirmar a integridade dos objetos e o resultado esperado para todos os itens
