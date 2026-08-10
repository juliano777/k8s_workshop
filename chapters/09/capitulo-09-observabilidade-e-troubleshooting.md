# Capítulo 9 — Observabilidade e troubleshooting

> **Objetivos de aprendizagem**
> Ao final deste capítulo, você será capaz de:
> 1. Dominar o kubectl logs em todas as variações e explicar o papel (e os limites) do metrics-server.
> 2. Instalar a stack Prometheus + Grafana e navegar em métricas e dashboards essenciais.
> 3. Diagnosticar metodicamente os estados de falha de Pods: CrashLoopBackOff, ImagePullBackOff, OOMKilled e Pending.
> 4. Depurar problemas de rede e DNS com um roteiro em camadas.
> 5. Investigar nós NotReady e falhas do control plane.
> 6. Usar eventos como linha do tempo do cluster e acelerar o dia a dia com k9s e stern.

> **A tese do capítulo**: troubleshooting não é talento, é **método**. Quem tem um roteiro resolve às 3h da manhã o que a intuição não resolve às 15h. Este capítulo entrega os roteiros — e quase todos os problemas usados como exemplo você já viu (ou provocou de propósito) nos capítulos anteriores.

---

## 9.1 Logs e métricas

Observabilidade clássica tem três pilares: **logs** (o que aconteceu, em texto), **métricas** (números ao longo do tempo) e **traces** (o caminho de uma requisição entre serviços — citaremos ao final). Comecemos pelos dois que todo cluster precisa.

### 9.1.1 kubectl logs e metrics-server

**De onde vêm os logs?** Do contrato firmado no Capítulo 2: containers logam em **stdout/stderr**; o runtime grava em arquivos no nó (`/var/log/pods/...`); o kubelet os serve; o `kubectl logs` os busca. Nenhuma mágica — e duas consequências importantes:

1. App que loga em arquivo interno é **invisível** para o kubectl (corrija o app, ou use um sidecar que faça *tail* para stdout — Capítulo 3).
2. Logs moram **no nó**: morreu o nó, morreram os logs — a motivação para agregadores (adiante).

**O arsenal completo do kubectl logs** (memorize os cinco primeiros):

```bash
kubectl logs <pod>                          # o básico
kubectl logs <pod> -f                       # follow: tempo real
kubectl logs <pod> --previous               # ★ do container ANTERIOR ao crash —
                                            #   o comando nº 1 do CrashLoopBackOff (9.2.1)
kubectl logs <pod> -c <container>           # Pod multi-container: escolha qual
kubectl logs deploy/api                     # via controller (um Pod qualquer dele)
kubectl logs -l app=api --prefix --tail=20  # TODOS os Pods da label, identificados
kubectl logs <pod> --since=10m              # janela de tempo
kubectl logs <pod> --timestamps             # quando o app não põe timestamp
```

Limites do modelo: logs somem com o nó/rotação, não são pesquisáveis entre Pods, não têm retenção. Em produção, um **agregador** coleta tudo (DaemonSet — Capítulo 3! — de Fluent Bit/Promtail em cada nó) e centraliza (Loki, Elasticsearch, ou o serviço da nuvem). Arquitetura para conhecer; a instalação fica como extensão do laboratório.

**metrics-server — o termômetro instantâneo.** Você o instalou no Capítulo 7 para o HPA. Entenda agora seu papel exato: ele coleta CPU/memória **atuais** dos kubelets e serve a Metrics API — que alimenta o `kubectl top` e o HPA. E só:

```bash
kubectl top nodes                            # visão instantânea por nó
kubectl top pods -A --sort-by=memory         # os glutões do cluster
kubectl top pods -n loja-prod --containers   # por container
```

- **Não guarda histórico** (só o agora), não tem alertas, não tem outras métricas. É termômetro, não prontuário.
- Uso tático: "o nó está saturado *agora*?", "qual Pod come a memória?", conferir se os requests do Capítulo 7 batem com a realidade.

Para histórico, correlação e alertas — o prontuário completo — precisamos da próxima seção.

### 9.1.2 Stack Prometheus + Grafana (instalação básica)

**Prometheus** é o padrão de fato de métricas no mundo cloud-native (segundo projeto da CNCF, depois do próprio Kubernetes). Seu modelo em quatro ideias:

1. **Pull**: o Prometheus **raspa** (`scrape`) endpoints HTTP `/metrics` periodicamente — os alvos apenas expõem números (lembra do padrão *adapter* e da annotation `prometheus.io/scrape` dos Capítulos 3?).
2. **Séries temporais com labels**: cada métrica é um nome + pares chave/valor — `http_requests_total{pod="api-7d4...", code="500"}` — e as labels permitem fatiar por qualquer dimensão (a mesma filosofia dos labels do Kubernetes, não por acaso).
3. **PromQL**: a linguagem de consulta que transforma séries em respostas ("taxa de erros 5xx por serviço nos últimos 5 min").
4. **Service discovery nativo de Kubernetes**: o Prometheus consulta a API e descobre sozinho o que raspar — Pods novos entram no monitoramento sem configuração manual (o modelo declarativo rendendo frutos de novo).

**Grafana** é a camada visual: dashboards sobre o Prometheus (e outras fontes). **Alertmanager** completa o trio: recebe alertas disparados por regras PromQL e roteia (Slack, e-mail, PagerDuty).

**Instalação — o caminho de produção, kube-prometheus-stack.** O chart Helm `kube-prometheus-stack` empacota tudo: Prometheus (via **Prometheus Operator** — Capítulo 10 acenando de novo), Grafana com dashboards prontos, Alertmanager, node-exporter (métricas de SO por nó, um DaemonSet) e kube-state-metrics (métricas dos *objetos*: réplicas desejadas vs. prontas, restarts...).

> Usaremos o Helm aqui pela primeira vez, três capítulos antes de estudá-lo (Capítulo 11) — como usuário, você só precisa de dois comandos; como estudioso, espere pelo capítulo dele.

```bash
# Helm (instale a CLI: script oficial ou gerenciador de pacotes)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitor prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace

kubectl get pods -n monitoring        # prometheus, grafana, alertmanager, exporters...
```

**Primeiro passeio:**

```bash
# Grafana (usuário admin; a senha mora num Secret — Capítulo 5 na prática):
kubectl get secret -n monitoring monitor-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
kubectl port-forward -n monitoring svc/monitor-grafana 3000:80
# http://localhost:3000 → Dashboards → pasta "Kubernetes": explore
#   "Compute Resources / Namespace (Pods)": uso vs. REQUESTS vs. LIMITS do Capítulo 7!

# Prometheus direto:
kubectl port-forward -n monitoring svc/monitor-kube-prometheus-st-prometheus 9090
# http://localhost:9090 → Status ▸ Targets (o que está sendo raspado) e Graph
```

**Cinco consultas PromQL para levar no bolso** (cole no Graph do Prometheus):

```promql
# 1. Pods reiniciando (a caça ao CrashLoop):
increase(kube_pod_container_status_restarts_total[1h]) > 0

# 2. CPU real por Pod (compare com os requests!):
sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (pod)

# 3. Memória de trabalho por Pod (a que conta para o OOMKill):
sum(container_memory_working_set_bytes{container!=""}) by (pod)

# 4. Throttling de CPU (o "limite controverso" do Cap. 7 aparecendo como latência):
rate(container_cpu_cfs_throttled_periods_total[5m])

# 5. Réplicas desejadas vs. disponíveis (deploy travado? nó caído?):
kube_deployment_status_replicas_unavailable > 0
```

E um gostinho de **alerta** — a stack já vem com dezenas de regras prontas (grupo `kubernetes-apps`: pods em crash, deploys incompletos...); veja em Prometheus → Alerts. Definir os seus e rotear no Alertmanager fica como extensão.

> **Traces, para completar o mapa**: em microsserviços, "qual serviço deixou a requisição lenta?" pede *distributed tracing* — padrão **OpenTelemetry**, backends como Jaeger/Tempo. Território pós-curso; saiba que o pilar existe.

**Exercício de fixação 9.1**
1. Por que `kubectl logs` não mostra nada para um app que grava em `/var/log/app.log` dentro do container? Dê as duas soluções (uma ideal, uma paliativa) e diga qual capítulo ensinou a paliativa.
2. metrics-server vs. Prometheus: preencha — quem alimenta o HPA? Quem responde "como estava a memória ontem às 14h"? Quem dispara alertas? Por que os dois coexistem?
3. Explique o modelo *pull* do Prometheus e por que o service discovery do Kubernetes o torna "zero configuração" para Pods novos.
4. Usando as consultas do bolso: monte o raciocínio PromQL para provar que um serviço sofre de throttling de CPU e correlacione com a decisão de manter/remover limits (Capítulo 7).

---

## 9.2 Troubleshooting sistemático

**O método universal, antes dos casos.** Grave este fluxo — ele resolve 90% dos incidentes:

```
1. kubectl get pods -o wide          ─ qual o STATUS? RESTARTS? em que nó?
2. kubectl describe pod <pod>        ─ leia os EVENTS (a causa quase sempre está aqui)
3. kubectl logs <pod> [--previous]   ─ o que o APP diz (ou disse antes de morrer)?
4. kubectl get events --sort-by=...  ─ o contexto do namespace/cluster
5. Formule hipótese → teste → corrija → CONFIRME que voltou ao normal
```

A ordem importa: **describe antes de logs** (Events apontam a categoria do problema; logs explicam o conteúdo). Agora, os três grandes grupos.

### 9.2.1 Diagnóstico de Pods (CrashLoopBackOff, ImagePullBackOff, OOMKilled)

**Árvore de decisão pelo STATUS do `get pods`:**

```
Pending            → nem foi agendado/iniciado    → caso P
ImagePullBackOff   → não conseguiu baixar imagem  → caso I
CrashLoopBackOff   → inicia e morre, em loop      → caso C
OOMKilled          → morto por memória            → caso O
Running mas "ruim" → probes? tráfego? recursos?   → caso R
```

**Caso P — Pending: o scheduler não achou lugar (ou algo trava a criação).**

```bash
kubectl describe pod <pod> | grep -A6 Events
```

Os três recados clássicos do scheduler e suas leituras (todos são conteúdo do Capítulo 7):

- `Insufficient cpu/memory` → os **requests** não cabem em nó algum. Reduza requests, libere carga ou adicione nós (o runbook 6.4.4; na nuvem, o Cluster Autoscaler agiria).
- `didn't match Pod's node affinity/selector` / `had untolerated taint` → suas regras de posicionamento não deixam alternativa (lembra da 4ª réplica Pending do lab 7?). Revise affinity/taints.
- Sem evento de scheduler, mas Pending → olhe volumes: PVC `Pending` segura o Pod (Capítulo 5 — há StorageClass? provisioner? `WaitForFirstConsumer` esperando?).

**Caso I — ImagePullBackOff / ErrImagePull: o kubelet não baixa a imagem.**

```bash
kubectl describe pod <pod> | grep -B2 -A6 Failed
```

Checklist na ordem de probabilidade:

1. **Typo/tag inexistente** (`nginx:1.99-inexistente` — você provocou isso no Capítulo 3!): confira nome e tag; `crictl pull <imagem>` direto no nó tira a dúvida.
2. **Registry privado sem credencial**: `pull access denied` → faltou o `imagePullSecrets` (Capítulo 5/8) ou o Secret está errado/no namespace errado.
3. **Rede/DNS do nó** até o registry: proxy corporativo, firewall (Capítulo 6), registry fora do ar.
4. Rate limit do Docker Hub (o famoso `toomanyrequests`): autentique ou use um mirror.

**Caso C — CrashLoopBackOff: o container inicia e morre; o kubelet reinicia com espera crescente** (o backoff do Capítulo 3: 10s→20s→...→5min).
Pergunta certa: *por que o processo termina?* — e a resposta está no log **do container que morreu**, não do atual:

```bash
kubectl logs <pod> --previous               # ★ o comando do capítulo
kubectl describe pod <pod> | grep -A4 "Last State"
#   Last State: Terminated / Reason: Error / Exit Code: 1
```

Leitura do **exit code**:

| Exit code | Tradução | Para onde olhar |
|---|---|---|
| 1, 2... (baixo) | erro do app (exceção, config) | logs --previous: stacktrace, "connection refused", env faltando (ConfigMap/Secret certos? — Cap. 5) |
| 137 (128+9, SIGKILL) | morte forçada — **OOMKill** (veja caso O) ou liveness matando | describe: Reason OOMKilled? probes com histórico de falha? |
| 143 (128+15, SIGTERM) | encerramento "educado" que virou loop | liveness agressiva? startup lenta sem startupProbe? (Cap. 3) |
| 126/127 | comando não executável/não encontrado | command/args do manifesto vs. imagem |

Causa recorrente e sorrateira: **liveness probe mal calibrada** matando um app saudável-porém-lento — o Capítulo 3 avisou; o describe mostra `Liveness probe failed` antes de cada restart. Correção: startupProbe ou thresholds realistas.

**Caso O — OOMKilled: o kernel matou por estouro do limit de memória** (a assimetria do Capítulo 7: CPU estrangula, memória executa).

```bash
kubectl describe pod <pod> | grep -B1 -A3 OOMKilled     # Exit Code: 137
```

Decisão em duas perguntas: o consumo é **legítimo** (app realmente precisa de mais → suba o limit — o VPA em modo recomendação do Cap. 7 dá o número) ou é **vazamento** (cresce sem teto → o limit está fazendo o trabalho dele; conserte o app)? A consulta 3 do bolso (9.1.2) plota a curva que diferencia os dois: platô = legítimo; rampa infinita = vazamento.

**Caso R — Running, mas "não funciona":** o Pod está de pé e o problema é outro:

```bash
kubectl get pods                   # READY 0/1? → readiness falhando → fora do Service (Cap. 4)
kubectl describe pod <pod>         # Readiness probe failed: ...
kubectl exec -it <pod> -- sh       # dentro: o processo escuta na porta? config carregada?
```

READY `0/1` com o app "funcionando" = quase sempre readiness apontando para path/porta errada — ou uma dependência fora (comportamento *correto*, lembre-se: é para isso que a readiness existe).

### 9.2.2 Diagnóstico de rede e DNS

A promessa do Capítulo 4 ("boa parte dos problemas de rede são DNS ou selectors") vira agora um roteiro em camadas — teste **de dentro para fora**, e pare na camada que falhar:

```bash
# Prepare um canivete de rede no namespace afetado:
kubectl run debug --rm -it --image=nicolaka/netshoot -n <ns> -- bash
```

**Camada 1 — O Service tem endpoints?** (a causa nº 1 de "serviço fora do ar")

```bash
kubectl get endpointslices -l kubernetes.io/service-name=<svc> -n <ns>
```
- **Vazio** → ou o **selector não casa** com label alguma (compare `kubectl get pods --show-labels` com o selector — o "cola errada" do Capítulo 3), ou os Pods **não estão Ready** (readiness — e você volta ao caso R).
- Com IPs → próxima camada.

**Camada 2 — O DNS resolve?**

```bash
# no pod debug:
nslookup <svc>                       # nome curto (mesmo ns)
nslookup <svc>.<ns>.svc.cluster.local
```
- Falhou → é DNS: o CoreDNS está bem? (`kubectl get pods -n kube-system -l k8s-app=kube-dns`, logs dele) — e a pergunta do Capítulo 8: **há NetworkPolicy de egress sem a exceção do kube-dns?** (a pegadinha que você viveu no lab 8).
- Resolveu → próxima.

**Camada 3 — O ClusterIP responde?**

```bash
curl -sv --max-time 3 http://<ClusterIP>:<porta>
```
- Nome resolve mas IP não responde → kube-proxy/regras no nó (raro) — ou, muito mais provável, **NetworkPolicy bloqueando** (Capítulo 8: teste rotulando o pod debug com a label permitida) ou porta errada (`port` vs `targetPort` do Service — confira o manifesto!).

**Camada 4 — O Pod responde diretamente?**

```bash
kubectl get pods -o wide             # pegue o IP do Pod
curl -sv --max-time 3 http://<IP-do-pod>:<targetPort>
```
- Pod responde, Service não → o problema é o Service (portas, selector) — volte às camadas 1/3 com essa certeza.
- Pod **não** responde → o app não escuta onde você pensa: `kubectl exec <pod> -- ss -tlnp` (em que porta/interface o processo escuta? `127.0.0.1` em vez de `0.0.0.0` é clássico em app mal configurado).

**Camada 5 — De fora do cluster** (NodePort/Ingress): o funil do Capítulo 4 na ordem inversa — o Ingress Controller está de pé (`kubectl get pods -n ingress-nginx`)? Os logs dele mostram a requisição (`kubectl logs -n ingress-nginx <controller> -f` enquanto você faz o curl)? A regra de host/path casa (describe do Ingress; 404 do controller = regra não casou; 503 = backend sem endpoints → **Camada 1**)? O TLS/Secret existe?

Repare como o roteiro **converge**: quase todo caminho termina em endpoints (selector/readiness), NetworkPolicy ou porta errada. São os três suspeitos de sempre.

### 9.2.3 Diagnóstico de nós e do control plane

**Nó NotReady** — o roteiro (relembre: você já viveu isso no Teste 5 do Capítulo 6):

```bash
kubectl describe node <nó>
# 1. Conditions: MemoryPressure? DiskPressure? PIDPressure?  ← o nó avisa o que falta
# 2. Events: "kubelet stopped posting node status" ← kubelet mudo (caiu? rede?)
```

No próprio nó (SSH):

```bash
systemctl status kubelet && journalctl -u kubelet -f --no-pager | tail -50
systemctl status containerd
df -h                                # DiskPressure: kubelet começa a DESPEJAR Pods e
                                     # recusa novos; imagens antigas são coletadas (GC)
```

As causas de sempre, todas velhas conhecidas: kubelet parado (reinicie e leia o journal), **cgroup driver desalinhado** (o crash-loop do Capítulo 6!), disco cheio (limpe imagens: `crictl rmi --prune`), certificado do kubelet expirado, **swap religado** após reboot (o fstab que não foi editado — Capítulo 6), rede do nó.
Enquanto isso, o cluster reage sozinho: taint `not-ready:NoExecute`, 5 minutos de tolerância, despejo — a cadeia completa que o Capítulo 7 destrinchou.

**Control plane doente** — sintomas: `kubectl` lento/`connection refused`, objetos que não reconciliam, `kubectl get componentstatuses` (obsoleto, mas ainda informativo em labs). O roteiro no cp-1:

```bash
# Os static pods (Capítulo 6!) estão de pé?
crictl ps | grep -E 'apiserver|etcd|scheduler|controller'
# Se o apiserver caiu, o kubectl NÃO funciona — por isso o crictl, que fala direto
# com o containerd. Logs sem kubectl:
crictl logs <id-do-container-do-apiserver> 2>&1 | tail -30
# ou: sudo tail -f /var/log/pods/kube-system_kube-apiserver-*/*/*.log
```

Cadeia de dependências para raciocinar: **etcd → apiserver → todo o resto**. etcd fora (disco cheio? — ele é sensível a latência de disco; corrupção? → o restore do 6.4.3 é o plano) derruba o apiserver; apiserver fora congela o cluster (mas os apps continuam — a lição da Topologia A). Scheduler/controller-manager fora = sintomas seletivos (Pods novos ficam Pending sem evento algum; Deployments não reagem) com apps intocados.

E o lembrete de arquitetura que organiza tudo: *os manifests estão em `/etc/kubernetes/manifests/` e o kubelet os vigia* — um erro de digitação ali (após um upgrade manual, por exemplo) derruba o componente; o journal do kubelet conta a história.

**Exercício de fixação 9.2**
1. Um Pod está Pending sem nenhum evento de scheduler. Duas hipóteses bem diferentes (uma do Capítulo 5, outra do 9.2.3) — quais e como distinguir?
2. `CrashLoopBackOff` com Exit Code 137, mas **sem** `OOMKilled` no describe. Qual o segundo suspeito e que linha do describe o entrega?
3. Reconstrua o diagnóstico do lab do Capítulo 8: após aplicar default-deny com egress, apps falham com nomes mas funcionam por IP. Em qual camada do roteiro 9.2.2 isso cai e qual a correção?
4. `kubectl` retorna `connection refused` no cluster do Capítulo 6. Monte a sequência de comandos (sem kubectl!) para descobrir se o culpado é o apiserver ou o etcd.
5. Um nó entra em DiskPressure. Descreva a reação automática do kubelet e dois comandos para liberar espaço.

---

## 9.3 Eventos e auditoria

### 9.3.1 kubectl events e ferramentas auxiliares (k9s, stern)

**Eventos: a linha do tempo do cluster.** Cada componente (scheduler, kubelet, controllers) registra o que faz como objetos Event — você os leu o curso inteiro no describe; agora, o acesso direto:

```bash
kubectl events --for pod/<pod>                # linha do tempo de UM objeto
kubectl events --types=Warning               # só os problemas do namespace
kubectl get events -A --sort-by=.lastTimestamp | tail -30   # o "diário" do cluster
kubectl get events -w                         # tempo real (deixe rodando num terminal
                                              #  durante QUALQUER operação de risco)
```

(O subcomando moderno `kubectl events` melhora ordenação e filtros do velho `get events`; use-o quando disponível.)

Dois limites e suas consequências:

- **Retenção de ~1 hora** (padrão): evento é diagnóstico do *agora*, não histórico. Investigação de ontem exige métricas (kube-state-metrics guardou os contadores — consulta 1 do bolso!) ou um exportador de eventos para o agregador de logs.
- Eventos ≠ **auditoria**: eventos dizem o que o *sistema* fez; o **audit log do API server** diz o que *cada usuário/SA* pediu (quem deletou o namespace? com que credencial? — as perguntas do RBAC do Capítulo 8). Habilitá-lo é configuração do apiserver (audit policy) — fica o mapa e a distinção conceitual, que cai em entrevista.

**k9s — o cockpit do cluster no terminal.** Interface TUI sobre o kubeconfig: navegue por recursos, veja logs, describe, delete, port-forward — tudo a uma tecla, respeitando seu RBAC:

```bash
# instalação: gerenciador de pacotes ou release do GitHub; depois apenas:
k9s
# :pods (ou :deploy, :svc, :events...)  l=logs  d=describe  s=shell  0=todos os ns
# e o modo "xray" (:xray deploy) que desenha a cadeia Deployment→RS→Pod do Capítulo 3
```

O ganho não é estético: é **velocidade de ciclo** — as cinco etapas do método (9.2) viram segundos. Em incidente, isso é ouro.

**stern — logs de muitos Pods, de uma vez.** O `kubectl logs -l` melhorado: multi-Pod, multi-container, colorido, com regex, sobrevivendo a restarts (novos Pods entram no stream sozinhos — essencial durante um rolling update):

```bash
stern api                        # tudo que casa com "api" no nome
stern -l app=api --since 10m     # por label, últimos 10 min
stern api -c app                 # só o container "app" (ignora sidecars)
stern api --exclude "healthz"    # silencie o ruído das probes
# caso de uso matador: acompanhar um canary (Cap. 7) com
stern -l app=web --template '{{.PodName}} {{.Message}}{{"\n"}}' | grep ERROR
```

**O kit do plantonista, consolidado** — o que este capítulo espera que você tenha à mão:

```
2 termômetros : kubectl top / dashboards Grafana
1 método      : get → describe (Events!) → logs (--previous) → events → hipótese
3 roteiros    : Pods (árvore de status) · Rede (5 camadas) · Nós/CP (kubelet → crictl)
2 aceleradores: k9s (navegar) · stern (logs em massa)
1 memória     : Prometheus (o que aconteceu quando você não estava olhando)
```

**Exercício de fixação 9.3**
1. Por que "o evento sumiu" não significa "o problema não aconteceu"? Como investigar um restart de ontem às 4h com as ferramentas deste capítulo?
2. Diferencie evento de auditoria com um exemplo: "o Pod X foi despejado" vs. "quem escalou o Deployment para zero?". Qual mecanismo responde cada um?
3. Durante um rolling update problemático, por que `stern -l app=web` é superior a `kubectl logs deploy/web -f`? (Duas razões técnicas.)
4. Monte seu "kit do plantonista" pessoal: para cada item do quadro acima, escreva o comando exato que você usaria no cluster do Capítulo 6.

---

## Laboratório consolidado do capítulo — a sala de escape

Formato diferente: **quebre de propósito, diagnostique com o método, conserte**. Para cada cenário, anote: sintoma → comando revelador → causa → correção. (Ideal em dupla: um quebra, o outro conserta.)

```bash
minikube start --nodes 2   # ou o cluster do Capítulo 6
kubectl create namespace lab9 && kubectl config set-context --current --namespace=lab9

# ── Cenário 1: a imagem fantasma
kubectl create deploy c1 --image=nginx:1.99-nao-existe
# diagnóstico esperado: get → ImagePullBackOff → describe → Failed pull → corrija a tag

# ── Cenário 2: o crash com testemunha
kubectl run c2 --image=busybox:1.36 -- sh -c 'echo "config invalida: falta DB_HOST"; exit 1'
# esperado: CrashLoopBackOff → logs --previous revela a mensagem → exit code 1 no describe

# ── Cenário 3: a morte por memória
kubectl run c3 --image=polinux/stress --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"c3","image":"polinux/stress","resources":{"limits":{"memory":"64Mi"}},"command":["stress","--vm","1","--vm-bytes","128M"]}]}}'
# esperado: OOMKilled, exit 137 → decisão: limit baixo ou app guloso?

# ── Cenário 4: o serviço sem ninguém
kubectl create deploy c4 --image=nginxinc/nginx-unprivileged:1.27
kubectl create svc clusterip c4 --tcp=80:8080 --dry-run=client -o yaml | \
  sed 's/app: c4/app: c4-typo/' | kubectl apply -f -
# esperado: camada 1 → endpointslices VAZIO → selector não casa → conserte o Service

# ── Cenário 5: o Pod que não fica pronto
kubectl create deploy c5 --image=nginxinc/nginx-unprivileged:1.27 --dry-run=client -o yaml > c5.yaml
# (edite: readinessProbe httpGet em /nao-existe porta 8080) e aplique
# esperado: READY 0/1, Running → describe: Readiness probe failed 404 → corrija o path

# ── Cenário 6: a régua que não cabe
kubectl run c6 --image=nginx:1.27 \
  --overrides='{"spec":{"containers":[{"name":"c6","image":"nginx:1.27","resources":{"requests":{"cpu":"64"}}}]}}'
# esperado: Pending → describe: Insufficient cpu → requests realistas

# ── Cenário 7 (cluster kubeadm): o nó mudo
# num worker: sudo systemctl stop kubelet → observe NotReady, Conditions, e os 5 min
# do taint not-ready (Cap. 7) → religue e explique cada etapa do que viu

# ── Cenário 8: síntese com Prometheus
# com a stack instalada, use as 5 consultas do bolso para ENCONTRAR os estragos
# dos cenários 2 e 3 sem olhar o kubectl (restarts e memória) — a memória do cluster

kubectl delete namespace lab9
```

---

## Resumo do capítulo

- **Logs**: stdout/stderr → nó → kubelet → `kubectl logs` (com `--previous` como comando de ouro pós-crash); produção agrega via DaemonSet (Fluent Bit/Loki). **metrics-server** = termômetro instantâneo (top/HPA); **Prometheus + Grafana** (kube-prometheus-stack) = histórico, PromQL, dashboards e alertas — com service discovery automático.
- **Método**: get → describe (**Events primeiro**) → logs → events → hipótese→teste→confirmação. Pods: **Pending** (requests/affinity/PVC), **ImagePullBackOff** (tag/credencial/rede), **CrashLoopBackOff** (`--previous` + exit code: 1=app, 137=OOM/probe, 143=SIGTERM), **OOMKilled** (legítimo vs. vazamento), **Running 0/1** (readiness).
- **Rede em 5 camadas**: endpoints → DNS → ClusterIP → Pod direto → borda (Ingress) — convergindo nos três suspeitos: selector/readiness, NetworkPolicy, porta errada. **Nós**: Conditions + journal do kubelet (cgroup, disco, swap, certificado); **control plane**: `crictl` quando o kubectl morre, cadeia etcd→apiserver→resto, manifests estáticos sob vigília do kubelet.
- **Eventos** = linha do tempo volátil (~1h; para trás disso, Prometheus/kube-state-metrics); **auditoria** = quem pediu o quê (audit log do apiserver). **k9s** acelera a navegação; **stern** acompanha logs de frotas de Pods — o kit do plantonista.

**Ponte para o Capítulo 10**: você agora enxerga e conserta o cluster — e já cruzou várias vezes com softwares que fazem isso *sozinhos*: o operator do Calico, o Prometheus Operator, o cert-manager, o CloudNativePG prometido. Chegou a hora de abrir essa caixa: como o Kubernetes é estendido com CRDs e como os Operators codificam o conhecimento operacional que você acabou de adquirir.
