## MODIFIED Requirements

### Requirement: Instalação segura e isolada de TEQ
Após instalação, Classic AQ e seus jobs SHALL permanecer desabilitados e nenhum
batch SHALL ser selecionado automaticamente. O pacote MUST NOT tocar mensagens,
filas, jobs, ADR ou evidências TEQ. A instalação SHALL persistir uma
configuração de paralelismo do Scheduler desabilitada por padrão, com limite
validado, sem iniciar workers até ativação explícita.

#### Scenario: Estado após instalação

- **WHEN** instalação e pós-verificação terminam com sucesso
- **THEN** gate/job estão desabilitados, não há seleção automática, o limite de
  paralelismo não inicia workers e TEQ fica inalterado

#### Scenario: Configuração de paralelismo inválida

- **WHEN** o administrador informa um limite de workers inválido
- **THEN** a configuração falha antes de habilitar qualquer job ou selecionar
  batch
