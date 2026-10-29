# BuildGCE — suspensão: modelo OFFLINE / DRY-RUN

**Não é controlador de produção. Não implementa nem chama Google Cloud
Compute Engine, Pub/Sub, IAM, Firestore, Cloud Run, e-mail, notificações ou
`instances.suspend`. Não importa credenciais.** Nenhuma decisão deste módulo
autoriza suspender uma máquina: `eligible_for_final_recheck=True` só indica
que um controlador externo autenticado poderia iniciar a **última
revalidação transacional**, ainda sujeito a aprovação expressa.

## Regressões executáveis sem infraestrutura

```sh
python3 -m unittest discover -s workstations/tests -p 'test_suspend_policy_dry_run.py' -v
```

A CI executa este teste na etapa de avaliação NixOS, sem identidade GCP
ou recursos pagos. O período de idle de **2h** e a idade máxima proposta de
observação de **60s** são parâmetros para homologação, não autorização.

Guardas: VM por projeto/zona/nome/**instance ID** em allowlist; `RUNNING`;
ausência comprovada de interação **e** trabalho (inclusive agentes aguardando
LLM com CPU quase zero) **e** atividade relevante de recursos; leases,
sessões e estado de veto frescos; geração de resume sem alteração; política
financeira independente com gasto **real**, BRL, ciclo mensal, orçamento
autenticado, `costAmount > budgetAmount == R$400` (nunca previsão).
Informação ausente/contraditória/inconclusiva => **DENY**.

Aviso precisa ter aceitação confirmada pelo provedor de e-mail e timestamp
durável. Uma sessão gráfica conectada também exige notificação gráfica
confirmada. O prazo é **3600 segundos INTEIROS** desde aceitação;
em `t=3599` DENY, em `t=3600` apenas elegibilidade a nova verificação.
O veto tem escopo próprio por proposta de idle ou mês de budget.
A mini-ledger pura testa reenvios, deduplicação, eventos fora de ordem,
invalidação por retomada e travessia de ciclo. **Veto e eventos de
encerramento/retomada autenticados não podem ser descartados apenas por
terem sequência menor que a última notificação processada**; somente
event IDs repetidos, identidade incorreta ou autenticação ausente são
descartados. Isso é um teste offline: **não oferece
persistência, locks, autenticação real nem entrega de notificação**.

## Obrigações antes de produção

Controlador fora da VM, IAM mínimo, armazenamento com CAS/transações e
auditoria, autenticação de eventos e cliente, observações seguras de
jobs/tmux/SSH, origem de budget/recibo de envio do provedor, e-mail com
POST protegido, UI XRDP efetivamente visível, proteção contra races,
janela de 60 dias de estado suspenso e testes de uma VM descartável
**equivalente**. Validar o mesmo `boot_id`, PIDs, XMonad, `DISPLAY`,
marcador **em RAM** e áudio nos dois sentidos após `instances.resume`.
`stop/start/reset/delete` não são fallback e o gate anterior segue
desabilitado. Incerteza => deixar RUNNING e registrar incidente.

Contrato canônico:
`klarkc/broker/contracts/2026-10-29-session-preserving-lifecycle-v2.md`.
