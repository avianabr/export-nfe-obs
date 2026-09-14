# classic-aq-deployment-configuration Specification

## Purpose

Provide a single, safe and inspectable local configuration contract for preparing
and operating the Classic AQ deployment in a new PDB.

## Requirements

### Requirement: Fonte única de configuração não secreta

O sistema SHALL fornecer um único arquivo local não versionado para todos os
valores de instalação: endpoint HTTPS S3-compatible, bucket, prefixo,
referência de credencial, mapeamento de origem, limite de inflight, senhas de
conexão com o PDB. Um orquestrador SHALL carregar essa fonte uma vez e executar
provisionamento, criação de credencial, pré-verificação e configuração na ordem
prescrita.

#### Scenario: Preparação de um PDB novo

- **WHEN** o administrador preenche o arquivo local protegido uma única vez
- **THEN** provisioning, criação de credencial, preflight e configure usam os
  mesmos valores sem solicitar parâmetros novamente

#### Scenario: Arquivo local ausente ou incompleto

- **WHEN** o arquivo local não existe ou contém marcador não substituído
- **THEN** o comando aplicável falha antes de DDL, de persistir mapeamento ou de
  ativar gate/job

### Requirement: Segredos somente na sessão do orquestrador

O sistema SHALL solicitar de forma oculta, apenas na sessão do orquestrador, as
senhas de `SYS` e `NFE_OWNER`, access key e secret key S3. Ele MUST gerar uma
senha aleatória não exibida para o runtime técnico e limpar os valores ao fim.
O template MUST documentar a função de cada parâmetro não secreto e avisar que
o arquivo não pode ser versionado. Os templates, scripts versionados, saída de
verificação e configuração persistida MUST NOT expor esses segredos.

#### Scenario: Acesso humano separado

- **WHEN** um auditor ou operador de purge humano precisa de acesso
- **THEN** o DBA concede a role privada correspondente a uma identidade humana
  individual aprovada, sem o deploy criar ou assumir essa conta

#### Scenario: Criação de credencial S3

- **WHEN** o operador executa o orquestrador
- **THEN** ele informa as chaves S3 uma vez, sem arquivo secreto auxiliar, e o
  processo usa a referência de credencial da fonte não secreta

### Requirement: Inspeção segura da configuração efetiva

O sistema SHALL oferecer um comando somente-leitura para exibir a configuração
efetiva persistida e os valores operacionais derivados, sem mostrar senhas,
access keys, secret keys, tokens ou conteúdo de credenciais.

#### Scenario: Conferência antes do teste funcional

- **WHEN** o administrador executa a inspeção como owner autorizado
- **THEN** ele obtém endpoint, bucket, prefixo, referência de credencial,
  mapeamento de origem, host ACL derivado e estado de gate/job, sem dados
  secretos
