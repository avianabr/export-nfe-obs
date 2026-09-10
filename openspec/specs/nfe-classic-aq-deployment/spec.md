# nfe-classic-aq-deployment Specification

## Purpose

Disponibilizar uma instalação mínima e controlada do runtime de migração de NF-e
com transporte Oracle Classic AQ em ambientes distintos da PoC original.

## Requirements

### Requirement: Pacote de instalação mínimo e determinístico

O sistema SHALL instalar em ordem determinística somente os objetos necessários
ao runtime Classic AQ, declarando executores, pré-requisitos e scripts. Ele MUST
falhar antes de DDL quando faltar pré-requisito obrigatório.

#### Scenario: Instalação em ambiente elegível

- **WHEN** o administrador executa o ponto de entrada em PDB elegível
- **THEN** runtime, filas RAW Classic AQ, controles, workers, monitor, jobs
  desabilitados e visões operacionais são instalados na ordem documentada

#### Scenario: Pré-requisito ausente

- **WHEN** uma dependência obrigatória não está disponível
- **THEN** o pacote informa a ausência e não inicia instalação parcial

### Requirement: Provisionamento idempotente dos principals internos

O sistema SHALL provisionar ou validar `NFE_MIGRATION_RUNTIME`, `NFE_AUDITOR`
e `NFE_PURGE_ADMIN`, suas roles privadas e os privilégios mínimos do runtime.
Ele MUST NOT criar, alterar ou parametrizar o owner/tabela da origem NF-e; esses
e seus grants de leitura permanecem dependências externas. Um principal interno
incompatível MUST interromper a instalação sem alteração automática.

#### Scenario: Novo PDB com origem externa provisionada

- **WHEN** `SYS` executa provisioning em PDB novo com a origem NF-e e
  pré-requisitos externos disponíveis
- **THEN** os principals internos são criados ou validados antes do runtime

#### Scenario: Principal interno incompatível

- **WHEN** usuário ou role interno existente não possui a forma declarada
- **THEN** a distribuição informa o conflito e não o recria, remove ou amplia

### Requirement: Configuração externa sem segredos versionados

O sistema SHALL fornecer templates para valores do ambiente e MUST NOT conter
senhas, tokens, chaves privadas, URIs de bucket de produção ou credenciais.

#### Scenario: Configuração de destino

- **WHEN** o administrador prepara um ambiente novo
- **THEN** ele fornece credencial, ACL e localização por parâmetros ou scripts
  locais não versionados

### Requirement: Acesso portátil S3-compatible

O sistema SHALL acessar Object Storage exclusivamente por endpoint, bucket,
prefixo, ACL e referência de credencial S3-compatible. Packages MUST NOT
depender de API, URI ou autenticação específica de provedor.

#### Scenario: Configuração compatível

- **WHEN** endpoint, bucket, prefixo, ACL e credencial válidos são fornecidos
- **THEN** o runtime constrói e acessa objetos pelo mesmo contrato portátil

#### Scenario: Configuração inválida

- **WHEN** falta valor obrigatório ou o endpoint não atende ao contrato
- **THEN** pré-verificação ou configuração falha antes de ativar transporte/jobs

### Requirement: Mapeamento persistido e dinâmico da origem NF-e

O sistema SHALL persistir owner, tabela, coluna CLOB e colunas de identificador,
chave, data e situação. Packages MUST resolver owner, tabela e CLOB em tempo de
execução e MUST NOT conter identificadores fixos de origem.

#### Scenario: Origem configurada pelo cliente

- **WHEN** o administrador persiste um mapeamento válido
- **THEN** packages usam a origem configurada sem alterar outros principals

#### Scenario: Mapeamento inválido

- **WHEN** owner, tabela ou coluna não existe, tem tipo inadequado ou não é
  acessível
- **THEN** a configuração falha com motivo identificável e não é ativada

### Requirement: Instalação segura e isolada de TEQ

Após instalação, Classic AQ e seus jobs SHALL permanecer desabilitados e nenhum
batch SHALL ser selecionado automaticamente. O pacote MUST NOT tocar mensagens,
filas, jobs, ADR ou evidências TEQ.

#### Scenario: Estado após instalação

- **WHEN** instalação e pós-verificação terminam com sucesso
- **THEN** gate/job estão desabilitados, não há seleção automática e TEQ fica
  inalterado

### Requirement: Verificação e rollback sem dados de teste

O sistema SHALL oferecer pós-verificação somente de metadados e rollback que
desabilite transporte/jobs sem apagar origem, objetos, filas TEQ ou evidências.

#### Scenario: Rollback operacional

- **WHEN** o administrador executa rollback
- **THEN** seleção e jobs são desabilitados e dados/evidências são preservados

### Requirement: Runbook guiado e teste funcional controlado

O sistema SHALL fornecer runbook com executor, comando, resultado, falha e
critério de avanço para cada fase, incluindo teste opt-in de uma NF-e existente.

#### Scenario: Execução guiada

- **WHEN** o administrador segue o runbook em ambiente elegível
- **THEN** ele decide cada fase por resultados observáveis sem consultar a PoC

#### Scenario: Teste funcional básico

- **WHEN** o administrador testa uma NF-e autorizada existente
- **THEN** o roteiro usa batch isolado e uma mensagem explícita, confirma objeto
  S3-compatible e `VERIFIED`, sem job permanente, purge ou TEQ
