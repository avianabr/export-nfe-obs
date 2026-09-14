## Context

O worker atual calcula SHA-256, executa `PUT_OBJECT`, baixa o BLOB por
`GET_OBJECT` e recalcula SHA-256. O benchmark de 10.000 itens/5 workers levou
2.521 segundos. A prova OCI isolada produziu PUT 200, HEAD 200 com
`Content-Length` e `content-md5`, e DELETE 204. O endpoint OBS atual não
completou um contrato `HEAD` autenticado pelo `DBMS_CLOUD`.

## Goals / Non-Goals

**Goals:**

- Eliminar `GET_OBJECT` do caminho bem-sucedido somente para OCI.
- Manter `VERIFIED` condicionado à evidência exigida pela estratégia do item.
- Preservar o comportamento atual como fallback para todo outro provedor.

**Non-Goals:**

- Criar agora uma estratégia rápida para OBS, AWS ou qualquer outro provedor.
- Aceitar `ETag` ou metadado SHA-256 OCI isolado como hash de conteúdo.
- Alterar AQ, redelivery, concorrência do Scheduler ou TEQ.

## Decisions

### Estratégia explícita e estável por item

A instalação e a configuração receberão `storage_provider` como parâmetro
inicial obrigatório, com enum `S3_COMPATIBLE` ou `OCI_NATIVE`. Não haverá
inferência por hostname. A configuração derivará uma estratégia com default
`FULL_DOWNLOAD_SHA256`; somente `OCI_NATIVE` aprovado pode selecionar
`OCI_MD5_HEAD`. Cada item gravará o modo efetivo no processamento, evitando que
troca posterior de configuração mude o significado da evidência já persistida.

### Credential selecionada no fluxo de instalação

O fluxo atual de credential será separado em duas rotas. Para
`S3_COMPATIBLE`, preserva access key/secret ou token existente e as URIs atuais.
Para `OCI_NATIVE`, usa a sobrecarga OCI de `DBMS_CLOUD.CREATE_CREDENTIAL` com
`user_ocid`, `tenancy_ocid`, `private_key` e `fingerprint`; a chave privada só é
recebida em prompt oculto e não é impressa ou persistida em script. O instalador
não pede dados S3 na rota OCI, nem dados OCI na rota S3.

O primeiro escopo OCI é signing key, que foi a forma comprovada pelo harness.
Resource principal poderá ser uma extensão futura, pois exige configuração do
principal no banco; a identidade da VM que executa o cliente não é, por si só,
uma credential disponível para o PL/SQL no banco.

### URI de objeto por adaptador

A conversão hoje feita por `object_uri` — endpoint HTTPS para `s3://` — passa a
ser exclusiva de `S3_COMPATIBLE`. O adaptador OCI monta e persiste a URL HTTPS
canônica `https://objectstorage.<region>.oraclecloud.com/n/<namespace>/b/<bucket>/o/<key>`.
Essa diferença é necessária porque `DBMS_CLOUD.SEND_REQUEST` assina a chamada
OCI HTTPS; convertê-la para `s3://` perde o contrato da API. A chave lógica do
objeto continua igual e é sempre persistida separadamente de `object_uri`.

### `OCI_MD5_HEAD`

O adaptador OCI usa `DBMS_CLOUD.SEND_REQUEST` contra a API HTTPS OCI com
credential de signing key. Calcula bytes, MD5 e SHA-256 no BLOB UTF-8, envia
`Content-MD5` e `If-None-Match: *`, e pode gravar `opc-meta-sha256` para
auditoria. Após PUT, faz `HEAD` e exige `Content-Length` e `content-md5`
iguais aos valores de origem. O SHA-256 de metadado não decide integridade.

### Checksums adicionais OCI postergados

O OCI Object Storage suporta `SHA256`, `SHA384` e `CRC32C` como checksums
adicionais ao MD5. Eles não integram esta implementação: o contrato comprovado
para o adaptador atual é `Content-MD5` no PUT e `content-md5` no HEAD. Uma
mudança futura poderá introduzir, preferencialmente, `SHA256`, desde que um
harness com `DBMS_CLOUD.SEND_REQUEST` comprove os headers de envio e retorno.
`SHA384` será considerado somente para exigência criptográfica específica;
`CRC32C`, para necessidade de desempenho ou upload multipart. Até lá, nenhum
checksum adicional será considerado evidência confirmada pelo serviço.

### `FULL_DOWNLOAD_SHA256`

É o adaptador atual, mantido como fallback: PUT seguido de GET completo e
comparação SHA-256. Será selecionado para OBS e todo provedor sem estratégia
aprovada. Isso é um fallback deliberado e não ETag/metadata best-effort.

### Pré-verificação OCI

Antes de habilitar OCI, um harness com objeto único sob prefixo isolado comprova
PUT com `Content-MD5`, HEAD de tamanho/MD5 e DELETE. A evidência armazenada não
contém corpo nem segredo. Falha mantém o fallback habilitado.

### Dados, reconciliação e auditoria

`NFE_MIGRATION_ITEM` ganhará colunas anuláveis para modo, bytes, algoritmo e
checksums de origem/destino, versão/identificador e instante HEAD. Reconciliação
exige evidência adequada ao modo de cada item. Download por amostragem continua
como auditoria OCI, fora do worker crítico.

## Risks / Trade-offs

- MD5 é menos resistente que SHA-256, mas é o checksum que OCI valida e expõe
  no contrato testado; SHA-256 continua disponível para auditoria.
- Configuração incorreta do modo poderia reduzir a garantia; default fallback,
  pré-verificação e persistência do modo mitigam o risco.
- A otimização OCI não aumenta desempenho nos demais provedores até que suas
  capacidades sejam projetadas e comprovadas separadamente.
- A OCI real não permite induzir, no ambiente de integração, um `HEAD` com
  `content-md5` ou `Content-Length` ausente/divergente. A cobertura aceita
  nesta mudança executa os fluxos OCI bem-sucedido, fallback, redelivery e
  objeto preexistente; a rejeição de campos ausentes/divergentes é verificada
  no runtime. Um mock ou adaptador injetável permanece fora do escopo por
  decisão explícita e poderá ser proposto futuramente.

## Migration Plan

1. Adicionar `storage_provider`, configuração e colunas com default
   `FULL_DOWNLOAD_SHA256`.
2. Separar criação/validação de credential S3-compatible e OCI nativa;
   separar construção de URI `s3://` e HTTPS OCI e implementar adaptadores e
   worker mantendo o fallback intacto.
3. Habilitar `OCI_MD5_HEAD` apenas para OCI após pré-verificação aprovada.
4. Testar OCI, fallback e redelivery; então repetir benchmark 10.000/5 workers.
5. Rollback: definir `FULL_DOWNLOAD_SHA256`; itens existentes permanecem
   legíveis e não exigem reprocessamento.
