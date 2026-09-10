## Purpose

Disponibilizar uma instalação mínima e controlada do runtime de migração de
NF-e com transporte Oracle Classic AQ em ambientes distintos da PoC original.

## ADDED Requirements

### Requirement: Pacote de instalação mínimo e determinístico
O sistema SHALL fornecer um ponto de entrada versionado que instale, em ordem
determinística, somente os objetos necessários ao runtime de migração com
Classic AQ. O pacote MUST declarar os usuários de execução, os pré-requisitos e
os scripts incluídos; ele MUST falhar antes de executar DDL quando um
pré-requisito obrigatório não estiver atendido.

#### Scenario: Instalação em ambiente elegível
- **WHEN** o administrador executa o ponto de entrada em um PDB elegível com
  os pré-requisitos declarados
- **THEN** o runtime, as filas Classic AQ, os controles de transporte, os
  workers, o monitor, os jobs desabilitados e as visões operacionais ficam
  instalados na ordem documentada

#### Scenario: Pré-requisito ausente
- **WHEN** uma conta, privilégio, recurso de Object Storage ou configuração
  obrigatória não estiver disponível
- **THEN** o pacote informa o pré-requisito ausente e não inicia a instalação
parcial do runtime

### Requirement: Provisionamento idempotente dos principals internos
O sistema SHALL provisionar ou validar os usuários internos
`NFE_MIGRATION_RUNTIME`, `NFE_AUDITOR` e `NFE_PURGE_ADMIN`, suas roles privadas
e os privilégios mínimos necessários ao runtime. O sistema MUST NOT criar,
alterar ou parametrizar o owner da tabela-fonte NF-e; esse owner, seus grants de
leitura e a tabela permanecem uma dependência externa configurada pelo
administrador. Um usuário, role ou privilégio interno incompatível MUST
interromper a instalação sem alteração automática.

#### Scenario: Novo PDB com somente a origem NF-e provisionada
- **WHEN** o administrador executa o entry point de provisioning como `SYS`
em um PDB novo que contém o owner/tabela de NF-e e os pré-requisitos externos
- **THEN** os usuários e roles internos do Classic AQ são criados ou validados
antes da instalação do runtime

#### Scenario: Principal interno incompatível
- **WHEN** um usuário ou role interno existente não possui a forma declarada
- **THEN** a distribuição informa o conflito e não recria, remove ou amplia o
principal automaticamente

### Requirement: Configuração externa por ambiente sem segredos versionados
O sistema SHALL fornecer templates e instruções para que os valores específicos
do ambiente sejam fornecidos pelo administrador. O pacote versionado MUST NOT
conter senhas, tokens, chaves privadas, URIs de bucket de produção ou credenciais
de Object Storage.

#### Scenario: Configuração de destino
- **WHEN** o administrador prepara a configuração de um novo ambiente
- **THEN** ele informa a credencial, ACL e localização de Object Storage por
  parâmetros ou scripts locais não versionados, sem alterar os artefatos
  versionados

### Requirement: Acesso portátil a Object Storage S3-compatible
O sistema SHALL acessar Object Storage exclusivamente pelo contrato
S3-compatible. A configuração por ambiente MUST conter endpoint S3-compatible,
bucket, prefixo e referência à credencial, sem versionar seu material secreto.
Packages e scripts de runtime MUST NOT depender de APIs, URIs ou autenticação
específicas de um provedor de nuvem.

#### Scenario: Configuração para provedor compatível com S3
- **WHEN** o administrador fornece um endpoint, bucket, prefixo, ACL e
  credencial S3-compatible válidos
- **THEN** o runtime constrói e acessa os objetos usando o contrato
  S3-compatible, independentemente do provedor que opera o bucket

#### Scenario: Endpoint não compatível ou configuração incompleta
- **WHEN** o endpoint não atende ao contrato S3-compatible ou faltam bucket,
  prefixo ou referência de credencial
- **THEN** a pré-verificação ou a gravação da configuração falha antes que o
  transporte ou os jobs sejam ativados

### Requirement: Mapeamento persistido e dinâmico da origem de NF-e
O sistema SHALL persistir, em configuração administrativa por ambiente, o
schema owner da tabela de NF-e (atualmente `NFE_OWNER`), o nome dessa tabela,
o nome da coluna CLOB que contém o conteúdo da NF-e e os nomes das colunas de
identificador, chave NF-e, data de emissão e situação necessárias à seleção.
As packages de seleção,
transferência, verificação, reconciliação e purge MUST resolver esses três
identificadores a partir da configuração em tempo de execução; o código de
runtime MUST NOT conter um nome fixo para o owner, a tabela ou a coluna CLOB de
origem. Os demais usuários e roles MUST permanecer no modelo atual e não fazem
parte desse mapeamento parametrizado.

#### Scenario: Migração com origem configurada pelo cliente
- **WHEN** o administrador persiste um owner, tabela e coluna CLOB válidos
  para o ambiente do cliente
- **THEN** as packages usam a origem configurada para acessar o conteúdo da
  NF-e sem depender de `NFE_OWNER`, `POC_NFE_DOCUMENT` ou `XML_CLOB` como
  identificadores de origem fixos; os demais principais do modelo atual não
  são alterados

#### Scenario: Mapeamento inválido ou inacessível
- **WHEN** o owner, a tabela ou a coluna CLOB configurados não existem, não
  têm o tipo esperado ou não são acessíveis ao owner das packages
- **THEN** a pré-verificação ou a gravação da configuração falha com o motivo
  identificável e o mapeamento inválido não é ativado

### Requirement: Instalação segura por padrão e isolada de TEQ
Após a instalação, o transporte Classic AQ SHALL permanecer desabilitado, os
jobs Classic AQ SHALL permanecer desabilitados e nenhum batch SHALL estar
selecionado automaticamente. O pacote MUST NOT criar, consumir, alterar ou
excluir mensagens, filas, jobs, incidentes ADR ou evidências de TEQ.

#### Scenario: Estado após instalação
- **WHEN** a instalação e a pós-verificação são concluídas com sucesso
- **THEN** Classic AQ está desabilitado, seus jobs estão desabilitados, não há
  batch selecionado automaticamente e os objetos TEQ existentes permanecem
  inalterados

### Requirement: Operação de verificação e rollback sem dados de teste
O pacote SHALL incluir uma pós-verificação somente de metadados e uma operação
de rollback que desabilite o transporte e seus jobs sem apagar conteúdo de
origem, objetos migrados, filas TEQ ou evidências. O pacote MUST NOT executar
seed de dados, benchmark, consumo de mensagens ou purge como parte da
instalação, verificação ou rollback.

#### Scenario: Rollback operacional
- **WHEN** o administrador executa o rollback do pacote
- **THEN** a seleção Classic AQ e seus jobs ficam desabilitados e os dados de
  origem, objetos migrados, filas TEQ e evidências permanecem preservados

### Requirement: Runbook guiado de instalação e teste funcional básico
O sistema SHALL fornecer um runbook versionado, em ordem de execução, para o
cliente conduzir: verificação de pré-requisitos, preparação da configuração
S3-compatible e da origem NF-e, instalação, pós-verificação, teste funcional
básico, leitura da evidência e rollback operacional. Para cada etapa, o runbook
MUST indicar usuário executor, comando ou script, resultado esperado, ação em
caso de falha e critério para prosseguir.

#### Scenario: Execução guiada pelo cliente
- **WHEN** o administrador segue o runbook em um ambiente elegível
- **THEN** ele consegue concluir ou interromper cada fase com base em resultados
observáveis, sem depender da sequência de scripts da PoC

#### Scenario: Teste funcional básico controlado
- **WHEN** o administrador opta pelo teste funcional usando uma NF-e de teste
  previamente autorizada no ambiente
- **THEN** o runbook orienta a admissão de um batch isolado, o processamento
  explícito de uma mensagem, a verificação de integridade do objeto
  S3-compatible e a confirmação de estado `VERIFIED`, sem habilitar jobs de
  forma permanente, executar purge ou tocar TEQ
