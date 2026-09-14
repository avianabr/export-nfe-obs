## Purpose

Definir integridade por item sem transferir novamente o XML quando o provedor
tem uma capacidade de checksum comprovada, preservando validação integral como
fallback seguro.

## ADDED Requirements

### Requirement: Integridade OCI por HEAD
Quando um batch usa `OCI_MD5_HEAD`, o sistema SHALL calcular tamanho e MD5 do
BLOB UTF-8, enviar o MD5 em `Content-MD5` e confirmar o upload OCI. Em seguida
MUST executar somente `HEAD` e comparar `Content-Length` e `content-md5` com a
evidência de origem antes de marcar o item como `VERIFIED`.

#### Scenario: Objeto OCI confirmado por HEAD

- **WHEN** o upload OCI aceita `Content-MD5` e o `HEAD` retorna tamanho e MD5
  idênticos aos calculados na origem
- **THEN** o item registra as evidências e alcança `VERIFIED` sem download
  completo

#### Scenario: Evidência OCI ausente ou divergente

- **WHEN** tamanho, MD5 ou confirmação do upload não é retornado ou diverge
- **THEN** o item MUST NOT alcançar `VERIFIED` e segue redelivery/exceção

### Requirement: Fallback por download integral
Quando um batch usa `FULL_DOWNLOAD_SHA256`, o sistema SHALL preservar o
algoritmo existente: calcular SHA-256 do BLOB UTF-8 de origem, executar o
upload, baixar o objeto inteiro e comparar SHA-256 antes de `VERIFIED`.

#### Scenario: Provedor sem capacidade HEAD aprovada

- **WHEN** o destino não está aprovado para `OCI_MD5_HEAD`
- **THEN** o worker usa `FULL_DOWNLOAD_SHA256` e não depende de `ETag`, MD5 de
  metadado ou semântica S3-compatible

### Requirement: Evidência auditável por modo
O sistema SHALL persistir modo efetivo, tamanho, algoritmo/checksum de origem e
destino, versão/identificador disponível e instante de verificação. Para OCI,
SHA-256 MAY ser persistido como metadado e para auditoria, mas MUST NOT ser
tratado como checksum validado pelo serviço.

#### Scenario: Auditoria OCI posterior

- **WHEN** o operador seleciona uma amostra de itens OCI já verificados
- **THEN** o sistema pode baixar o objeto e comparar SHA-256 sem alterar o
  processamento normal dos demais itens

### Requirement: Falha segura e isolamento entre provedores
O sistema MUST validar antes de ativar `OCI_MD5_HEAD` que o endpoint OCI aceita
`Content-MD5` e expõe tamanho/MD5 via `HEAD`. Falha MUST selecionar o fallback;
nenhum item pode alcançar `VERIFIED` com base em `ETag` isolado ou metadado não
validado.

#### Scenario: Contrato OCI não comprovado

- **WHEN** a pré-verificação OCI não comprova o contrato
- **THEN** `OCI_MD5_HEAD` não é ativado e o item usa o fallback

### Requirement: Escopo atual de checksum OCI
Nesta mudança, o sistema SHALL usar `Content-MD5` como a evidência de checksum
confirmada pelo serviço para `OCI_MD5_HEAD`. `SHA256`, `SHA384` e `CRC32C` MAY
serem adotados em uma mudança futura somente após validação, por
`DBMS_CLOUD.SEND_REQUEST`, dos headers de PUT e HEAD do algoritmo selecionado.
Esta mudança MUST NOT tratar um checksum adicional como confirmado pelo
serviço sem essa prova.

#### Scenario: Checksum adicional ainda não validado

- **WHEN** o operador considera `SHA256`, `SHA384` ou `CRC32C` para OCI
- **THEN** o runtime atual permanece em `OCI_MD5_HEAD` e a melhoria é tratada
  como escopo futuro
