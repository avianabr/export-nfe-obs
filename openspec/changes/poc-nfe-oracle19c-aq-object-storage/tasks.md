## 1. Descoberta e preparação do ambiente

- [x] 1.1 Confirmar release Oracle AI Database 26ai, recursos TEQ e disponibilidade/contratos de `DBMS_CLOUD`; registrar resultado go/no-go e evidências do ambiente alvo
- [x] 1.2 Provisionar bucket/prefixo da PoC, IAM, credencial, ACL/TLS e configurações de versionamento/retenção aprovadas; verificar upload e download manuais sem expor segredos
- [x] 1.3 Definir schemas, papéis e grants de owner, runtime, purge-admin e auditor; verificar com sessão runtime que `XML_CLOB` e a administração de purge não podem ser alterados/executados
- [x] 1.4 Levantar volume, tamanhos e distribuição temporal dos XMLs e capturar baseline de CPU, I/O, redo, undo e Streams Pool para dataset representativo

## 2. Fundamentos de dados e mensageria

- [x] 2.1 Criar tabelas de documento, batch, item, configuração, auditoria e reconciliação com constraints, índices e transições de estado; verificar unicidade por NF-e e integridade referencial
- [x] 2.2 Implementar auditoria append-only e consultas de métricas/estado do batch; verificar que eventos operacionais e administrativos são rastreáveis sem armazenar XML ou credenciais
- [x] 2.3 Criar e iniciar a Transactional Event Queue de payload RAW e sua exception queue com política inicial de retries; verificar enqueue, dequeue e encaminhamento de mensagem de teste para exceção
- [x] 2.4 Implementar configuração de pausa, limites de chunk, itens em voo e workers; verificar que as leituras de configuração restringem admissão sem remover backlog confirmado

## 3. Seleção e admissão histórica

- [x] 3.1 Implementar criação de batch com critérios auditáveis e validação dos limites; verificar rejeição de batch com parâmetros inválidos e persistência dos critérios válidos
- [x] 3.2 Implementar seleção de NF-es históricas elegíveis com chave de objeto determinística e unicidade por NF-e; verificar que documento já controlado não é incluído novamente
- [x] 3.3 Implementar inserção do item e enqueue do envelope de referência na mesma transação Oracle; verificar que commit torna item/mensagem visíveis juntos e rollback não deixa nenhum dos dois visível
- [x] 3.4 Implementar admission control por pausa, status de batch, limite máximo e itens em voo; verificar que cada condição impede novos chunks e que a retomada preserva o acervo admitido

## 4. Transferência idempotente por worker

- [x] 4.1 Implementar conversão segura de `CLOB` em BLOB `AL32UTF8`, cálculo de tamanho e SHA-256 e liberação de LOB temporário; verificar bytes com XMLs de tamanhos e caracteres variados
- [x] 4.2 Implementar dequeue transacional, validação de contrato e carregamento do item/documento; verificar que payload inválido não produz item `VERIFIED`
- [x] 4.3 Implementar derivação de object key, upload por `DBMS_CLOUD` e persistência de ETag/versionamento quando disponível; verificar que uma solicitação válida grava no prefixo e chave esperados
- [x] 4.4 Implementar verificação por download, tamanho e SHA-256 antes de confirmar `VERIFIED`; verificar que divergência de hash ou tamanho bloqueia a transição
- [x] 4.5 Implementar tratamento de objeto preexistente e entrega repetida; verificar recuperação após falha simulada entre `PUT_OBJECT` e commit sem criar chave lógica adicional, e bloqueio de objeto divergente sem sobrescrita
- [x] 4.6 Implementar classificação de falhas, rollback para erros transitórios e diagnóstico seguro; verificar redelivery TEQ após timeout/throttling simulado e ausência de confirmação prematura

## 5. Operação, exceções e reconciliação

- [x] 5.1 Implementar monitor da exception queue que preserva a correlação, marca `EXCEPTION` e emite alerta; verificar o fluxo completo após exceder `MAX_RETRIES`
- [x] 5.2 Implementar jobs `DBMS_SCHEDULER` inicialmente desabilitados para seleção, workers e reconciliação; verificar execução limitada, encerramento ocioso e resposta à pausa entre mensagens
- [x] 5.3 Implementar reconciliação de item e batch com contagens, bytes, presença de objeto e divergências de integridade; verificar que somente batch totalmente íntegro chega a `READY_FOR_APPROVAL`
- [x] 5.4 Implementar relatório de reconciliação e dashboard/consultas de backlog, retries, latência, throughput, workers, exceções e divergências; verificar visibilidade de batch sem progresso e de qualquer erro de integridade
- [x] 5.5 Executar benchmark com 1, 2, 4 e 8 workers e diferentes limites de admissão; registrar p50/p95/p99, throughput e impacto no banco para definir parâmetros da PoC

## 6. Aprovação, purge e validação final

- [x] 6.1 Implementar aprovação administrativa com bloqueio e revalidação do batch, identidade autenticada, comentário, evidência e auditoria; verificar rejeição sem reconciliação aprovada e transição válida para `APPROVED_FOR_PURGE`
- [x] 6.2 Implementar purge manual em chunks no pacote administrativo segregado, preservando a linha fiscal e revalidando pré-condições por chunk; verificar que somente `XML_CLOB` de itens verificados do batch aprovado é zerado
- [x] 6.3 Implementar reconciliação pós-purge e fechamento de batch; verificar que `PURGED` exige objetos íntegros, CLOBs ausentes, contagens consistentes e trilha completa de aprovação/execução
- [ ] 6.4 Executar a matriz de testes de concorrência, rollback, queda pós-upload, objeto idêntico/divergente, exception queue, pausa/retomada e negação de privilégios; publicar evidências e resultados da PoC
- [x] 6.5 Executar um batch representativo ponta a ponta com aprovação humana explícita e purge pequeno; verificar restauração amostral do Object Storage e documentar recomendações, limites e critérios para expansão
