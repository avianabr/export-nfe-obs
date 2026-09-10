## Context

O runtime Classic AQ validado está distribuído em scripts DDL e de segurança
numerados, entremeados com testes, dados sintéticos, benchmark e evidências da
PoC. A instalação em outro ambiente requer o mesmo conjunto de objetos e
dependências, mas não pode herdar estado, endpoints, credenciais ou operações
de teste da PoC. Consulte `proposal.md` para a motivação e a especificação da
change para o contrato observável.

## Goals / Non-Goals

**Goals:**

- Produzir uma distribuição SQL autocontida para instalar e configurar o
  runtime Classic AQ de forma revisável e repetível.
- Tornar explícitas as fases de pré-requisito, instalação sob os usuários
  corretos, configuração por ambiente, pós-verificação e rollback operacional.
- Manter a postura segura por padrão: transporte e job desligados até ativação
  posterior e deliberada.

**Non-Goals:**

- Provisionar infraestrutura, owner/tabela de origem NF-e, rede, bucket ou
  segredos.
- Migrar dados, criar NF-es sintéticas, processar mensagens, executar benchmark
  ou habilitar o transporte automaticamente.
- Alterar, reparar, descarregar ou remover o caminho TEQ e sua evidência ADR.
- Reestruturar a semântica de migração, Object Storage, reconciliação ou purge.

## Decisions

### Diretório de distribuição separado com manifest e entry points

Criar um diretório de deploy versionado, com manifest que lista versão,
pré-requisitos, ordem, usuário executor e scripts incluídos. Os entry points
irão separar pré-verificação, instalação, configuração de ambiente,
pós-verificação e rollback; cada um chamará apenas os artefatos de runtime
necessários.

Alternativa considerada: documentar uma ordem manual sobre `sql/ddl` e
`sql/security`. Rejeitada porque a seleção manual voltaria a incluir scripts de
validação e tornaria a implantação difícil de reproduzir.

### Reutilizar o runtime validado sem incorporar testes

A distribuição referenciará ou copiará os scripts de runtime necessários para
schema, auditoria, configuração de pipeline, transferência, reconciliação,
Classic AQ, admissão, worker, monitor, scheduler, dashboards e privilégios. Os
scripts de `testdata`, `validation`, `*_verify*`, benchmark e evidências não
farão parte do fluxo de instalação. Se um script atual misturar runtime e
verificação, a implementação o dividirá sem modificar o contrato de runtime.

Alternativa considerada: incluir toda a árvore `sql` como release. Rejeitada
porque criaria dados e operações de PoC em ambientes de destino.

### Provisionamento interno e configuração externa explícita

O primeiro entry point, executado como `SYS`, criará ou validará os usuários
internos `NFE_MIGRATION_RUNTIME`, `NFE_AUDITOR` e `NFE_PURGE_ADMIN`, suas roles
privadas e apenas os privilégios de sistema e objeto necessários às respectivas
APIs. Contas e roles existentes precisam ter a forma esperada; divergências
interrompem a instalação sem alteração automática. O pacote não cria nem altera
o owner da origem NF-e, pois ele pertence ao modelo de dados do ambiente.

Alternativa considerada: exigir que todas as contas fossem provisionadas fora
da distribuição. Rejeitada porque os principals internos fazem parte do
runtime entregue e impediriam uma instalação repetível em PDB novo.

### Configuração externa e explícita

O repositório conterá somente templates com marcadores e documentação de
parâmetros para credencial, ACL, localização de objetos, origem NF-e e limites.
O administrador prepara um arquivo local não versionado ou executa a
configuração com seus próprios valores; o manifest nunca registra valores
secretos nem endpoints de um ambiente. O owner da origem NF-e e seus grants de
leitura continuam externos e configuráveis; os usuários internos são tratados
pela etapa de provisioning.

Alternativa considerada: um script com valores padrão da PoC. Rejeitada porque
isso pode enviar dados ao bucket errado ou expor material sensível.

### Contrato único de Object Storage S3-compatible

O runtime e a distribuição tratarão endpoint S3-compatible, bucket, prefixo,
ACL e referência de credencial como a única interface de Object Storage. A
configuração formará URLs e chamadas de transferência a partir desse contrato,
sem ramificações para OCI Object Storage, Azure Blob, Google Cloud Storage ou
outros SDKs/protocolos proprietários. Material secreto continuará exclusivamente
no mecanismo local de credenciais do banco, fora do repositório.

Alternativa considerada: oferecer adaptadores por provedor. Rejeitada porque
aumentaria superfície de deploy e manutenção, enquanto S3-compatible é o
contrato portátil exigido para clientes de provedores desconhecidos.

### Mapeamento de origem persistido e identificadores SQL seguros

Uma tabela singleton de configuração de origem guardará o owner da origem
(hoje `NFE_OWNER`), o nome da tabela NF-e e a coluna CLOB. A API administrativa
validará nomes SQL simples, existência no dicionário, tipo CLOB e privilégio de
acesso antes de persistir o mapeamento. As packages obterão o mapeamento dessa
tabela e montarão apenas os identificadores validados para as instruções
dinâmicas inevitáveis; owner da origem, tabela e coluna de conteúdo não poderão
permanecer literais de runtime. Outros usuários e roles não serão afetados.

Além do owner, tabela e coluna CLOB, a configuração administrativa mapeará os
nomes das colunas de identificador numérico, chave NF-e, data de emissão e
situação. A implementação validará esses identificadores, seus tipos mínimos e
o privilégio de leitura antes de ativar o mapeamento; ela falhará de modo
legível se a tabela configurada não oferecer essa forma mínima.

Alternativa considerada: substituir identificadores com variáveis de SQL*Plus
durante o deploy. Rejeitada porque muda a origem por ambiente somente na
instalação, não persiste o mapeamento auditável e exigiria recompilação para
cada cliente.

### Idempotência conservadora e parada antecipada

O entry point verificará os pré-requisitos antes do primeiro DDL e scripts de
instalação validarão a forma esperada de objetos já existentes. Diante de um
objeto incompatível, a execução falhará sem corrigir, substituir ou apagar
automaticamente. O rollback será operacional: desabilita seleção e jobs, sem
dropar objetos ou dados.

Alternativa considerada: instalar com `DROP ...`/recriação. Rejeitada porque
seria destrutiva para um ambiente que já tenha batches ou evidências.

### Runbook operacional versionado e testável

O pacote incluirá um runbook Markdown que referencia os entry points e o
manifest em vez de repetir SQL solto. As seções serão: escopo e contas,
pré-requisitos, parâmetros S3-compatible e origem NF-e, instalação,
pós-verificação, teste funcional básico, interpretação de falhas, desativação e
rollback. Cada passo terá resultado esperado e bloqueio explícito para a etapa
seguinte.

O teste funcional será opt-in e usará uma NF-e de teste já existente, um batch
isolado e processamento explícito de uma única mensagem; ele não criará dados
sintéticos, não habilitará job permanentemente e não executará purge. Isso
preserva a separação entre instalação e carga/benchmark de produção.

Alternativa considerada: entregar somente scripts com comentários. Rejeitada
porque comentários não fornecem decisão operacional, tratamento de falha nem
trilha de evidência para o administrador do cliente.

## Risks / Trade-offs

- [Scripts existentes dependem de objetos criados em etapas não óbvias] →
  mapear dependências e validar o pacote em schema/PDB limpo antes da entrega.
- [Privilégios SYS variam entre ambientes] → declarar cada privilégio e conta
  por fase, com pré-verificação legível e sem concessões amplas implícitas.
- [Credencial ou ACL local é configurada incorretamente] → não ativar jobs ou
  transporte durante a instalação e exigir pós-verificação antes da ativação.
- [Endpoint de Object Storage usa contrato proprietário] → validar parâmetros
  S3-compatible e manter uma única implementação de transferência baseada nesse
  contrato.
- [Identificador de origem malformado introduz SQL dinâmico inseguro] → aceitar
  somente identificadores validados no dicionário e nunca concatenar valores
  não validados nas packages.
- [Execução repetida encontra objetos incompatíveis] → tratar incompatibilidade
  como erro seguro, preservando o estado existente para análise.

## Migration Plan

1. Inventariar dependências reais dos scripts Classic AQ validados e definir o
   manifest de runtime mínimo.
2. Criar a configuração persistida da origem NF-e, os entry points, templates
   não secretos e documentação operacional.
3. Executar pré-verificação e instalação em ambiente limpo com as contas
   declaradas; confirmar pós-verificação somente de metadados.
4. Entregar a ativação Classic AQ como etapa administrativa separada, após a
   validação local do ambiente.
5. Em caso de rollback, executar o entry point de desativação; ele não remove
   filas, dados de origem, objetos migrados ou artefatos TEQ.
