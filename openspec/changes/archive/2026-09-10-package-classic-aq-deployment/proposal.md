## Why

Os scripts atuais comprovam a PoC de AQ clássico, mas estão organizados junto
com validações, dados sintéticos, benchmarks e evidências específicas do PDB de
teste. Outros ambientes precisam de uma instalação repetível e mínima que não
crie dados de teste, não execute workers e não toque no backlog/evidência TEQ.

## What Changes

- Criar um pacote de deploy do transporte Classic AQ com um único ponto de
  entrada, ordem explícita e somente as dependências de runtime necessárias.
- Provisionar os usuários e roles internos do runtime Classic AQ, com
  privilégios mínimos e idempotência conservadora; o owner da tabela de NF-e
  permanece uma dependência externa configurável.
- Separar a configuração por ambiente (Object Storage, credenciais, ACLs,
  limites, origem de NF-e e ativação operacional) do artefato versionado, sem
  incluir segredos ou valores do ambiente de PoC.
- Padronizar todo acesso ao Object Storage no contrato S3-compatible, com
  endpoint, bucket e credencial informados pelo ambiente, sem acoplamento a um
  provedor de nuvem.
- Persistir o owner da origem de NF-e (hoje `NFE_OWNER`), a tabela de NF-e e a
  coluna CLOB de conteúdo como configuração validada por ambiente e fazer com
  que as packages resolvam essa origem em tempo de execução, sem nomes fixos
  desses três identificadores no código de runtime.
- Fornecer pré-verificações, pós-verificações e instruções de rollback seguro;
  a instalação permanece desabilitada e sem jobs ativos até a ativação
  administrativa explícita.
- Publicar um runbook passo a passo para o cliente validar pré-requisitos,
  instalar, configurar e executar um teste funcional básico e controlado.
- Excluir do pacote de instalação dados sintéticos, benchmarks, scripts de
  teste/validação, capturas ADR/TEQ e scripts de purge.

## Capabilities

### New Capabilities

- `nfe-classic-aq-deployment`: pacote mínimo, seguro e repetível para instalar
  e configurar o runtime do transporte Classic AQ em outro ambiente Oracle.

### Modified Capabilities

Nenhuma.

## Impact

- Afeta a organização e os pontos de entrada dos scripts SQL de schema,
  segurança, transferência, controle de pipeline, Classic AQ, worker, monitor,
  scheduler e observabilidade.
- Introduz documentação e templates de configuração por ambiente, sem alterar
  o contrato do envelope AQ, o formato de objeto ou a política de purge.
- Exige que a origem de NF-e configurada seja acessível ao owner das packages e
  tenha a forma de dados necessária ao fluxo de migração.
- Requer somente o owner/tabela de origem NF-e, endpoint, credencial e ACL
  S3-compatible fornecidos pelo ambiente de destino; os demais principals
  internos são provisionados pela distribuição.
