## 1. Prova de capacidade e seleção de estratégia

- [x] 1.1 Criar e executar harness OCI isolado com PUT `Content-MD5`, HEAD de tamanho/MD5/metadados e limpeza, sem imprimir segredo. Evidência: PUT 200, HEAD 200 e DELETE 204.
- [x] 1.2 Verificar OBS e a versão instalada de `DBMS_CLOUD`; registrar que não há contrato portátil comprovado (S3 URI com algoritmo não suportado e HTTPS com HTTP 400) e que ele usa fallback.
- [x] 1.3 Implementar `storage_provider` obrigatório (`S3_COMPATIBLE`/`OCI_NATIVE`), configuração com default `FULL_DOWNLOAD_SHA256`, habilitação controlada de `OCI_MD5_HEAD` e pré-verificação OCI; verificar que falha ou provedor não OCI preserva fallback. Validado pelo evento `OCI_HEAD_PROBE_PASSED` e pelo smoke S3 fallback.

## 2. Evidências e adaptadores

- [x] 2.1 Separar a criação/validação de credential por `storage_provider`: preservar credential S3-compatible e criar a credential OCI nativa por signing key sem expor segredo; verificar prompts e privilégios mínimos de ambas as rotas. Validado: orquestrador seleciona o script por provedor; prompts de segredo são ocultos; preflight exige somente `DBMS_CLOUD` e privilégios mínimos necessários.
- [x] 2.2 Estender o controle de item com modo efetivo, bytes, algoritmo/checksum de origem e destino, identificador/versionamento e instante HEAD, preservando linhas existentes. Validado no upgrade de schema e nos smoke tests OCI/S3.
- [x] 2.3 Implementar adaptador OCI com PUT por `DBMS_CLOUD.SEND_REQUEST`, `Content-MD5`, prevenção de sobrescrita e SHA-256 opcional como metadado; validar hashes sobre BLOB UTF-8. Validado por smoke OCI e rejeição de sobrescrita ORA-20412.
- [x] 2.4 Implementar HEAD OCI de tamanho/`content-md5` e adaptador fallback por GET/SHA-256; rejeitar campos OCI obrigatórios ausentes e ETag isolado. Validado: o runtime e a pré-verificação rejeitam MD5 ou tamanho nulos; OCI batch 46 confirmou itens por MD5/HEAD, e o fallback mantém GET/SHA-256.
- [x] 2.5 Alterar a construção de `object_uri` para selecionar `s3://` somente em `S3_COMPATIBLE` e URL HTTPS canônica em `OCI_NATIVE`; verificar que nenhum fluxo converte URL OCI em `s3://`. Validado pelos smoke tests OCI e S3.

## 3. Worker, reconciliação e auditoria

- [x] 3.1 Alterar worker para selecionar o modo do item: OCI via HEAD sem download, fallback via GET/SHA-256, antes de VERIFIED. Validado: batch 42 OCI e batch 44 S3 fallback chegaram a VERIFIED.
- [x] 3.2 Preservar rollback/redelivery para divergência, objeto preexistente ou modo inválido; tais itens não alcançam VERIFIED. Validado: objeto OCI preexistente rejeitado com `-20412`; modo inválido manteve item `QUEUED` e mensagem AQ em `WAIT` com `retry_count=1`.
- [x] 3.3 Atualizar reconciliação e dashboard com modo e evidências; batch só fica íntegro se cada item satisfaz a evidência exigida pelo próprio modo. Validado pela view para batches OCI 42 e S3 43/44.
- [x] 3.4 Criar auditoria amostral por download completo para itens OCI sem alterar o processamento normal. Validada para batch 42: `OCI_SAMPLE_AUDIT_1_OF_1`.

## 4. Validação e operação

- [x] 4.1 Criar testes de integração para OCI HEAD bem-sucedido, MD5/tamanho ausente ou divergente, fallback por download, redelivery e objeto preexistente, preservando isolamento TEQ. Validado: OCI HEAD bem-sucedido, fallback, redelivery e objeto preexistente; por decisão explícita, a ausência/divergência de headers HEAD fica coberta pela validação do runtime, pois a OCI real não permite simular essas respostas sem adicionar mock/adaptador injetável fora do escopo.
- [x] 4.2 Repetir benchmark de 10.000 NF-es com dez workers e comparar com baseline de 2.521 segundos. Resultado OCI: batch 46, 10.000 VERIFIED, 208 s, 48,1 itens/s; a comparação não isola HEAD de aumento de workers.
- [x] 4.3 Atualizar runbook, manifest e consultas operacionais com modos, pré-requisitos, fallback, auditoria e rollback, sem documentar segredos.
- [x] 4.4 Executar `openspec validate optimize-classic-aq-head-validation --strict` e `git diff --check`. Executado sem erros após a implementação e os smoke tests.

## Melhorias postergadas

- Checksum adicional OCI (`SHA256`, `SHA384` ou `CRC32C`) não faz parte desta
  mudança. Uma proposta futura deve primeiro comprovar, via
  `DBMS_CLOUD.SEND_REQUEST`, os headers de PUT e HEAD do algoritmo escolhido.
