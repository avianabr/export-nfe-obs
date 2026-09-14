# nfe-classic-aq-scheduler-parallelism Specification

## Purpose

Definir como o Oracle Scheduler executa múltiplos workers Classic AQ com limites,
visibilidade operacional e desligamento seguro por ambiente e batch.

## Requirements

### Requirement: Execução paralela explicitamente limitada

O sistema SHALL permitir configurar uma quantidade máxima positiva de workers
Scheduler para processamento Classic AQ. A configuração MUST permanecer
desabilitada até ativação explícita e MUST impedir que o número de execuções
ativas exceda o limite definido.

#### Scenario: Ativação controlada de workers

- **WHEN** um operador autorizado habilita o processamento paralelo com limite válido
- **THEN** o Scheduler inicia no máximo a quantidade configurada de workers

#### Scenario: Limite inválido

- **WHEN** o operador informa limite nulo, zero ou acima do máximo suportado
- **THEN** a configuração falha sem habilitar ou criar workers

### Requirement: Isolamento e recuperação de workers

O sistema SHALL associar cada execução paralela ao batch e à configuração
vigentes. Falha de um worker MUST preservar a mensagem para redelivery ou
exceção, sem interromper workers independentes nem confirmar item não verificado.

#### Scenario: Falha isolada de worker

- **WHEN** um worker encontra erro transitório durante o processamento
- **THEN** o item não alcança `VERIFIED`, sua mensagem permanece recuperável e
  os demais workers podem continuar dentro do limite configurado

### Requirement: Observabilidade de paralelismo

O sistema SHALL disponibilizar o limite configurado, contagem de workers
ativos, progresso por batch e falhas recentes sem expor payload, XML ou
credenciais.

#### Scenario: Inspeção operacional

- **WHEN** um operador consulta o dashboard durante um batch paralelo
- **THEN** ele visualiza workers ativos, itens processados, pendências e falhas
  suficientes para decidir entre aguardar, interromper ou investigar
