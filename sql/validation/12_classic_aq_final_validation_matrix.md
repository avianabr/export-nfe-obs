# Matriz final — AQ clássico

Execute no `PDB_POCRT_02` e preserve as saídas `PASS` já obtidas. Não execute
novamente os scripts que consomem as mensagens de evidência 43/44; a matriz
abaixo referencia as evidências realizadas nesta change.

| Controle | Evidência AQ clássico |
| --- | --- |
| Compatibilidade, RAW, retry e exception queue | `13_validate_classic_aq_19c_compatibility.sql`, `38_verify_nfe_classic_aq.sql` |
| Nomes e coexistência TEQ | `14_verify_classic_aq_names.sql`, baseline `12_capture_teq_preservation_baseline.sql` |
| Gate, admissão commit/rollback | `40_verify_nfe_classic_transport_config.sql`, batches 43/44 e `44_verify_nfe_classic_aq_admission_rollback.sql` |
| Sucesso, transient redelivery e exceção | `46_verify_nfe_classic_aq_worker.sql`, `47_verify_nfe_classic_aq_transient_redelivery.sql`, `49_verify_nfe_classic_aq_exception_monitor.sql` |
| Pausa, jobs e negação runtime | `51_verify_nfe_classic_aq_scheduler.sql`, `09_verify_classic_aq_runtime_denial.sql` |
| Dashboard, rollback operacional e preservação TEQ | `53_verify_nfe_classic_aq_operations_dashboard.sql`, `55_verify_nfe_classic_aq_operational_rollback.sql` |
| Fluxo final sem purge | `56_verify_nfe_classic_aq_end_to_end.sql` |

Ainda são necessárias as medições 1/2/4/8 workers da tarefa 5.3 antes de uma
decisão de continuidade. Nenhuma etapa desta matriz autoriza purge.
