## ADDED Requirements

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
