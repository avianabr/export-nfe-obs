## Purpose

Define os controles operacionais, a reconciliação e o tratamento de exceções necessários para operar e comprovar uma migração histórica de NF-e.

## ADDED Requirements

### Requirement: Retry e exception queue rastreáveis
O sistema SHALL permitir que falhas transitórias sejam tentadas novamente pela política da TEQ e SHALL identificar mensagens que excedam o máximo de tentativas na exception queue. Para cada exceção, SHALL correlacionar o item, registrar auditoria e expor o caso para intervenção operacional explícita.

#### Scenario: Máximo de tentativas excedido
- **WHEN** uma mensagem excede o limite configurado de tentativas da TEQ
- **THEN** o item correspondente é identificado como `EXCEPTION`, a evidência da mensagem é preservada e um alerta operacional é emitido

### Requirement: Reconciliação de batch como condição de aprovação
O sistema SHALL produzir uma execução de reconciliação por batch que compare itens, objetos, contagens e bytes de origem e destino. Um batch SHALL ficar `READY_FOR_APPROVAL` somente se a seleção estiver encerrada, todos os itens estiverem verificados e não houver falhas, exceções, objetos ausentes ou divergências de tamanho e hash.

#### Scenario: Reconciliação aprovada
- **WHEN** a reconciliação encontra todos os itens verificados, contagens e bytes equivalentes e nenhuma divergência
- **THEN** o batch é marcado como `READY_FOR_APPROVAL` e o relatório de evidência é associado ao batch

#### Scenario: Reconciliação com divergência
- **WHEN** a reconciliação encontra falha, exceção, objeto ausente ou divergência de integridade
- **THEN** o batch é bloqueado para aprovação e o relatório identifica as discrepâncias

### Requirement: Observabilidade e controle seguro da operação
O sistema SHALL registrar eventos de seleção, transferência, verificação, reconciliação, aprovação e purge em trilha de auditoria append-only. SHALL expor backlog, estados, retries, exception queue, throughput, latências, bytes, workers e divergências, e SHALL permitir pausa e retomada sem redescobrir o acervo já admitido.

#### Scenario: Pipeline pausado durante o processamento
- **WHEN** um operador autorizado pausa o pipeline
- **THEN** a admissão é interrompida e os workers terminam mensagens em curso de forma segura, preservando itens pendentes para retomada

#### Scenario: Falta de progresso ou divergência
- **WHEN** o backlog não progride pelo período configurado ou surge uma divergência de integridade
- **THEN** as métricas e a auditoria permitem identificar o batch, o item e a causa operacional para investigação
