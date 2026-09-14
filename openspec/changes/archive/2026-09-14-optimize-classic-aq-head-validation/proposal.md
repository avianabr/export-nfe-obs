## Why

O benchmark de 10.000 NF-es com cinco workers levou 2.521 segundos (3,97
itens/s). O worker atual baixa integralmente cada objeto após o upload somente
para recalcular o SHA-256, duplicando a transferência. A prova executada no OCI
mostrou que `HEAD` retorna tamanho e MD5 sem baixar o conteúdo; a mesma
capacidade não foi comprovada para o endpoint OBS/S3-compatible atual.

## What Changes

- Introduzir estratégias explícitas de integridade por destino: inicialmente
  `OCI_MD5_HEAD` e `FULL_DOWNLOAD_SHA256`.
- `OCI_MD5_HEAD` envia `Content-MD5` no upload, que o OCI valida, e compara em
  `HEAD` o `Content-Length` e `content-md5` retornados pelo serviço.
- `FULL_DOWNLOAD_SHA256` será o padrão e preservará, sem alteração, o fluxo
  atual de upload, download e comparação SHA-256 para OBS e qualquer provedor
  sem estratégia específica aprovada.
- Habilitar o modo OCI somente após pré-verificação com objeto descartável,
  credencial OCI de signing key e evidência não secreta de PUT/HEAD/DELETE.
- Tornar `storage_provider` um parâmetro inicial obrigatório da instalação e
  configuração. A criação de credential seleciona o contrato correspondente:
  credencial S3-compatible para `S3_COMPATIBLE` e credencial nativa OCI por
  signing key para `OCI_NATIVE`.
- Persistir o modo efetivo e as evidências adequadas ao modo por item; `ETag`
  nunca será aceito como checksum de conteúdo.
- Substituir a conversão universal do endpoint HTTPS para URI `s3://` por uma
  construção de URI orientada por `storage_provider`: S3 mantém `s3://`; OCI
  mantém a URL HTTPS canônica da API Object Storage.

### Melhorias OCI postergadas

O OCI Object Storage também oferece checksums adicionais `SHA256`, `SHA384` e
`CRC32C`. Esta mudança continua com `OCI_MD5_HEAD`, pois este é o contrato
validado pelo harness atual. A adoção de um checksum adicional está postergada
para uma mudança futura, após provar com `DBMS_CLOUD.SEND_REQUEST` o envio e o
retorno via `HEAD` dos headers OCI correspondentes. `SHA256` é a primeira
alternativa a avaliar; `SHA384` e `CRC32C` permanecem opções para requisitos
de segurança ou desempenho/multipart específicos.

## Capabilities

### New Capabilities

- `nfe-classic-aq-object-integrity`: integridade por provedor com caminho OCI
  baseado em HEAD e fallback seguro por download integral.

### Modified Capabilities

- `nfe-classic-aq-deployment`: configuração explícita e pré-verificação para
  habilitar a estratégia OCI, com fallback como comportamento padrão.

## Impact

- Afeta parâmetros iniciais, criação de credential, configuração de storage,
  dados de controle, worker Classic AQ,
  reconciliação, dashboard, testes e runbook.
- O acesso OCI usa HTTPS autenticado por `DBMS_CLOUD`; outros provedores não
  passam a depender de API, URI ou autenticação OCI.
- O SHA-256 pode continuar armazenado para auditoria, mas no OCI a confirmação
  do storage é `Content-MD5`, não SHA-256.
