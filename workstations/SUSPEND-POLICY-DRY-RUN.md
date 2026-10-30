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
autenticado, `costAmount > budgetAmount == R$560` (nunca previsão).
Informação ausente/contraditória/inconclusiva => **DENY**.

Aviso precisa ter aceitação confirmada pelo provedor de e-mail e timestamp
durável. Uma sessão gráfica conectada também exige notificação gráfica
confirmada. O prazo é **3600 segundos INTEIROS** desde aceitação;
em `t=3599` DENY, em `t=3600` apenas elegibilidade a nova verificação.
O veto tem escopo próprio por proposta de idle ou mês de budget.
A mini-ledger pura testa reenvios, deduplicação, eventos fora de ordem,
invalidação por retomada e travessia de ciclo. **Veto, encerramento e
retomada autenticados tornam-se tombstones monotônicos mesmo se chegarem
fora de ordem.** O cursor `last_sequence` agora representa só a sequência
CONTÍGUA processada (não o maior número visto), evitando que um recibo
de e-mail de sequência 2 permita ignorar um veto de sequência 1 ainda
pendente. Uma leitura simulada do ledger com identidade, geração,
mês, **projeto/zona/instance ID**, origem, integridade, frescor,
**tipos inteiros válidos** e `committed_sequence == contiguous_sequence`
é pré-condição da rechecagem; sem leitura ou com qualquer lacuna,
**DENY**, inclusive antes de o veto atrasado chegar. Conflitos de
identidade/seq também invalidam o ledger. A suíte testa todas as seis
permutações de entrega de dois recibos e um veto, conferindo o
prefixo contíguo e a permanência do tombstone de veto. O watermark committed precisa
vir de um **escritor transacional autenticado**, não de Pub/Sub nem do cliente.
Isso é um teste offline: **não oferece
persistência, locks, autenticação real nem entrega de notificação**.

## Obrigações antes de produção

Nenhuma flag `source_verified` simulada comprova autenticação real:
o controlador de produção deve provar o watermark em leitura transacional
com o veto/close atomicamente persistido e sincronizar a transição final
`suspend` com mutações concorrentes de veto. Não confiar em um consumidor
de eventos que veja lacunas ou em snapshot antigo.

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

## Integridade de timestamps e gerações no modelo offline

Campos temporais do candidato, ledger e eventos devem ser segundos Unix inteiros e não negativos (sem floats ou bool). IDs de geração devem ser inteiros positivos, nunca `True`/`False`. Python aceita `bool` como subtipo de `int`, o que poderia falsificar um relógio ou geração sem a validação de tipos. As regressões cobrem avisos e vetos de ambas as políticas, evento do provedor e leitura do ledger. Isto **não** substitui a autenticação, o registro durável ou a rechecagem transacional do controlador externo.
