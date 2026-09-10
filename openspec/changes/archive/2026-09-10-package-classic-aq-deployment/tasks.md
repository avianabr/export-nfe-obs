## 1. Definição do conteúdo de runtime

- [x] 1.1 Inventariar dependências transitivas dos scripts de runtime Classic AQ e registrar no manifest o script, usuário executor e ordem; verificar que nenhum script de `testdata`, `validation`, benchmark, evidência TEQ/ADR ou purge esteja incluído.
- [x] 1.2 Definir a estrutura versionada de distribuição, os entry points SQL e o guia de operação; verificar que um administrador consegue identificar a fase de pré-verificação, instalação, configuração, pós-verificação e rollback sem consultar scripts de PoC.

## 2. Pré-requisitos e configuração por ambiente

- [x] 2.0 Criar o entry point SYS de provisioning idempotente para `NFE_MIGRATION_RUNTIME`, `NFE_AUDITOR` e `NFE_PURGE_ADMIN`, suas roles privadas e privilégios mínimos; verificar que o owner/tabela-fonte NF-e, ACL, bucket e credential continuam externos e que um principal interno incompatível interrompe sem alteração automática. **Validada em clone em 2026-09-10: `NFE_AUDITOR` com autenticação `EXTERNAL` causou `ORA-20891` e permaneceu `EXTERNAL`/`OPEN`.**
- [x] 2.0a Criar o entry point `NFE_OWNER` para criar uma credential DBMS_CLOUD S3-compatible a partir de arquivo local protegido; verificar que acesso/segredo não são versionados e que uma credential existente não é substituída automaticamente. **Validada em 2026-09-10: `HUAWEI_OBS_CRED` permaneceu presente sem carregar o arquivo local de chaves.**
- [x] 2.1 Implementar a pré-verificação somente de metadados para PDB, contas, privilégios, DBMS_CLOUD, endpoint, bucket, prefixo, ACL e referência de credencial S3-compatible, além de objetos conflitantes; verificar que uma ausência falha antes de qualquer DDL de instalação. **Corrigida e validada em 2026-09-10: detectou grants AQ e ACL HTTP ausentes antes do runtime.**
- [x] 2.2 Criar a tabela e API administrativa de mapeamento da origem NF-e para owner da origem (hoje `NFE_OWNER`), tabela, coluna CLOB e colunas de identificador, chave, data e situação; verificar que a configuração é persistida, auditável por ambiente e não parametriza os demais usuários ou roles.
- [x] 2.3 Validar identificadores SQL, existência, tipo CLOB, forma mínima da tabela e privilégios de leitura antes de ativar o mapeamento; verificar que owner, tabela ou coluna inválidos falham sem alterar a configuração ativa.
- [x] 2.4 Substituir referências fixas à origem nas packages de seleção, transferência, verificação, reconciliação e purge pela resolução dinâmica do mapeamento validado; verificar por busca e teste que `NFE_OWNER`, `POC_NFE_DOCUMENT` e `XML_CLOB` não persistem como identificadores fixos de origem no runtime.
- [x] 2.5 Criar templates e instruções de configuração por ambiente, com marcadores para endpoint, bucket, prefixo, ACL e referência de credencial S3-compatible, origem NF-e e limites; verificar por busca automatizada que o pacote não contém segredos, endpoint da PoC ou integração específica de provedor.
- [x] 2.6 Criar o entry point de configuração que aplique somente valores fornecidos pelo administrador e preserve o estado desabilitado; verificar que ele não habilita Classic AQ, jobs ou batch automaticamente.
- [x] 2.7 Adaptar a configuração e as packages de transferência para construir acessos somente pelo contrato S3-compatible; verificar com um endpoint S3-compatible não pertencente ao provedor da PoC que upload, leitura e integridade usam o mesmo fluxo. **Validada em 2026-09-10 no Huawei OBS: URI `s3://`, item `VERIFIED` e SHA-256 de origem/objeto idênticos.**

## 3. Instalação mínima do runtime

- [x] 3.1 Criar o entry point de instalação do schema e componentes comuns necessários ao runtime e verificar a execução idempotente contra objetos com a forma esperada. **Corrigida e validada em 2026-09-10: os `CHECK` incluem `SELECTING` e `VERIFYING`; batch e item atingiram `VERIFIED`.**
- [x] 3.2 Incluir a instalação de filas Classic AQ, controle de transporte, admissão, worker, monitor, scheduler e dashboards na ordem declarada; verificar que as filas usam o contrato RAW Classic AQ e que o job é criado desabilitado.
- [x] 3.3 Integrar a política de privilégios mínimos ao provisioning dos usuários e roles internos declarados e verificar que callers de runtime não recebem acesso AQ direto.
- [x] 3.4 Garantir que objetos incompatíveis interrompam a instalação sem `DROP`, recriação ou alteração automática; verificar esse comportamento com um objeto conflitante controlado. **Validada em PDB novo em 2026-09-10: `NFE_DEPLOY_SOURCE_CONFIG` como `VIEW` causou `ORA-20810`, permaneceu `VIEW` e nenhum dos oito objetos adicionais de runtime foi criado.**

## 4. Verificação, rollback e documentação

- [x] 4.1 Implementar a pós-verificação somente de metadados e verificar o estado seguro: Classic AQ desabilitado, job desabilitado, nenhum batch selecionado e TEQ não referenciado.
- [x] 4.2 Criar o entry point de rollback operacional e verificar que ele desabilita seleção e jobs sem apagar dados de origem, objetos migrados, filas TEQ ou evidências.
- [x] 4.3 Publicar o runbook passo a passo com usuário executor, script/comando, resultado esperado, critério de avanço e ação diante de falha para pré-requisitos, configuração, instalação, pós-verificação e rollback; verificar que o cliente consegue seguir a sequência sem consultar a PoC.
- [x] 4.4 Documentar no runbook o teste funcional básico opt-in com uma NF-e de teste existente, batch isolado, processamento explícito de uma mensagem, verificação do objeto S3-compatible e estado `VERIFIED`; verificar que o roteiro não habilita jobs permanentemente, não cria dados sintéticos, não faz purge e não toca TEQ.

## 5. Validação integrada do pacote

- [x] 5.1 Executar a distribuição em ambiente limpo ou schema isolado com configuração local não secreta e verificar que todos os entry points concluem sem criar dados sintéticos nem consumir mensagens. **Validada em PDB limpo em 2026-09-10: provisioning, credential local, preflight, instalação, privilégios, configuração, rollback e pós-verificação concluídos; nenhuma mensagem foi consumida e TEQ não foi referenciado.**
- [x] 5.2 Executar as verificações de regressão do runtime Classic AQ aplicáveis após a instalação e registrar a evidência de que admissão, processamento, retry e observabilidade continuam disponíveis sem tocar TEQ. **Validada em 2026-09-10 no PDB isolado: 10.000 NF-es sintéticas; admissão/processamento com item e batch `VERIFIED`, SHA-256 idênticos no Huawei OBS; retry esgotado em `RETRY_COUNT=3`/`EXPIRED`; monitor registrou `queued=1, verified=1, exception=1`; configuração normal e estado seguro restaurados sem tocar TEQ.**
