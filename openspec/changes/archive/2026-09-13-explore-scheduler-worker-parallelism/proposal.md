## Why

O job atual do Scheduler chama um worker por execução e o teste de escala cria
jobs descartáveis fora do runtime. É necessário definir como executar vários
workers em paralelo de forma operacionalmente segura, observável e reversível.

## What Changes

- Investigar modelos de paralelismo do `DBMS_SCHEDULER` para workers Classic AQ
  (jobs individuais, chains ou jobs com múltiplos slaves).
- Definir limites de concorrência, propriedade dos jobs, ativação explícita,
  isolamento entre batches e desligamento seguro.
- Especificar métricas e evidências operacionais para throughput, erros,
  redelivery, filas e workers ativos.
- Criar um plano de teste controlado que compare execução serial e paralela sem
  habilitar jobs automaticamente nem tocar TEQ.

## Capabilities

### New Capabilities

- `nfe-classic-aq-scheduler-parallelism`: orquestração segura e observável de
  múltiplos workers Classic AQ pelo Oracle Scheduler.

### Modified Capabilities

- `nfe-classic-aq-deployment`: requisitos de instalação, configuração e
  rollback para o mecanismo de paralelismo do Scheduler.

## Impact

- `DBMS_SCHEDULER`, package de runtime, controles de configuração, dashboard,
  runbook e testes de escala.
- Exige preservar o gate desabilitado por padrão, o rollback sem perda de
  mensagens e o isolamento de TEQ.
