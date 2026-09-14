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

O sistema SHALL fornecer templates versionados neutros e uma fonte única de
valores não secretos do ambiente, preparada localmente fora do controle de
versão. Senhas, tokens, chaves privadas e chaves S3 MUST permanecer em arquivos
locais protegidos separados. O pacote MUST NOT conter esses segredos, URIs de
bucket de produção ou credenciais.

#### Scenario: Configuração de destino

- **WHEN** o administrador prepara um ambiente novo
- **THEN** ele fornece endpoint, bucket, prefixo, referência de credencial e
  mapeamento de origem uma única vez em arquivo local não secreto; fornece
  segredos somente nos arquivos locais protegidos próprios

#### Scenario: Template versionado

- **WHEN** um template do pacote é consultado ou copiado
- **THEN** ele contém marcadores neutros, sem valores executáveis específicos da
  PoC ou de produção

### Requirement: Acesso humano por identidades externas

O pacote SHALL criar as roles privadas de auditoria e purge, mas MUST NOT criar
ou assumir contas humanas para essas personas. O runbook MUST orientar o DBA a
conceder a role adequada a identidades humanas individuais aprovadas.

#### Scenario: Auditoria ou purge autorizado

- **WHEN** uma pessoa autorizada precisa executar uma função de auditoria ou
  purge
- **THEN** o DBA concede somente a role privada correspondente à identidade
  individual dessa pessoa

### Requirement: Acesso portátil S3-compatible

O sistema SHALL acessar Object Storage exclusivamente por endpoint HTTPS,
bucket, prefixo e referência de credencial S3-compatible. O host usado para a
ACL HTTP MUST ser derivado e validado a partir do endpoint configurado; o
administrador MUST NOT fornecê-lo como parâmetro independente. A etapa `SYS`
prescrita da instalação MUST criar ou preservar idempotentemente a permissão
HTTP de `NFE_OWNER` para esse host. Packages MUST NOT depender de API, URI ou
autenticação específica de provedor.

#### Scenario: Configuração compatível

- **WHEN** endpoint, bucket, prefixo e credencial válidos são fornecidos
- **THEN** o pré-check valida o endpoint e a etapa `SYS` da instalação deriva o
  host ACL, cria ou preserva a permissão HTTP correspondente para `NFE_OWNER`,
  e o runtime constrói e acessa objetos pelo mesmo contrato portátil

#### Scenario: Configuração inválida

- **WHEN** falta valor obrigatório, há marcador não substituído, o endpoint não
  é HTTPS ou sua ACL derivada não atende ao contrato
- **THEN** pré-verificação ou a etapa `SYS` da instalação falha antes de ativar
  transporte/jobs

### Requirement: Configuração explícita de estratégia de integridade

O sistema SHALL exigir `storage_provider` como parâmetro inicial de instalação
e configuração. Os valores permitidos MUST ser `S3_COMPATIBLE` e `OCI_NATIVE`.
O sistema SHALL configurar por destino um modo de integridade explícito, com
valor padrão `FULL_DOWNLOAD_SHA256`. `OCI_MD5_HEAD` MUST ser habilitado somente
para `OCI_NATIVE`, credencial OCI de signing key e prova de capacidade
registrada com sucesso. Provedores sem modo específico aprovado MUST permanecer
no fallback.

#### Scenario: Parâmetro de provedor ausente ou inválido

- **WHEN** `storage_provider` não é informado ou não pertence aos valores
  permitidos
- **THEN** instalação/configuração falha antes de criar credential, storage ou
  jobs

#### Scenario: Configuração OCI compatível

- **WHEN** endpoint OCI, bucket, prefixo e credencial de signing key válidos
  são fornecidos para `storage_provider=OCI_NATIVE` e a pré-verificação
  PUT/HEAD é aprovada
- **THEN** a configuração pode habilitar `OCI_MD5_HEAD`

#### Scenario: Provedor sem estratégia específica

- **WHEN** o destino é OBS, S3-compatible ou outro provedor sem capacidade
  própria comprovada, ou `storage_provider=S3_COMPATIBLE`
- **THEN** o runtime seleciona `FULL_DOWNLOAD_SHA256` e mantém a validação por
  download integral

#### Scenario: Pré-verificação OCI falha

- **WHEN** a credencial, PUT com `Content-MD5` ou HEAD OCI não atende ao
  contrato
- **THEN** `OCI_MD5_HEAD` não é habilitado e o modo permanece
  `FULL_DOWNLOAD_SHA256`, sem bloquear o processamento normal

### Requirement: Criação de credential orientada por provedor

O instalador SHALL criar ou validar a credential conforme `storage_provider`.
Para `S3_COMPATIBLE`, MUST usar o contrato existente de access key/secret ou
token compatível. Para `OCI_NATIVE`, MUST usar a sobrecarga OCI nativa de
`DBMS_CLOUD.CREATE_CREDENTIAL` com `user_ocid`, `tenancy_ocid`, `private_key` e
`fingerprint`; MUST NOT solicitar nem gravar credenciais S3 nesse caminho.

#### Scenario: Credential OCI nativa

- **WHEN** `storage_provider=OCI_NATIVE` é selecionado
- **THEN** o instalador solicita somente os parâmetros de signing key OCI e
  cria/valida uma credential OCI nativa sem exibir a chave privada

#### Scenario: Credential S3-compatible

- **WHEN** `storage_provider=S3_COMPATIBLE` é selecionado
- **THEN** o instalador mantém o fluxo de credential S3-compatible e não
  solicita OCIDs, fingerprint ou chave privada OCI

### Requirement: Construção de URI orientada por provedor

O runtime SHALL construir a URI de acesso ao objeto conforme
`storage_provider`. Para `S3_COMPATIBLE`, MUST manter a URI `s3://` usada por
`DBMS_CLOUD.PUT_OBJECT` e `GET_OBJECT`. Para `OCI_NATIVE`, MUST manter a URL
HTTPS canônica da API OCI no formato `/n/<namespace>/b/<bucket>/o/<object>`
para `DBMS_CLOUD.SEND_REQUEST`. O runtime MUST NOT converter
indiscriminadamente uma URL HTTPS OCI em `s3://`.

#### Scenario: URI OCI nativa

- **WHEN** `storage_provider=OCI_NATIVE` e um item é admitido ou processado
- **THEN** `object_uri` contém a URL HTTPS OCI canônica, usada pelo adaptador
  para PUT, HEAD e DELETE

#### Scenario: URI S3-compatible

- **WHEN** `storage_provider=S3_COMPATIBLE` e um item é admitido ou processado
- **THEN** `object_uri` contém a URI `s3://` atual, usada pelo adaptador de
  fallback de upload/download

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
