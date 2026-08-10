# Capítulo 7 — Scheduling, escalabilidade e resiliência

> **Objetivos de aprendizagem**
> Ao final deste capítulo, você será capaz de:
> 1. Configurar requests e limits, explicar as classes de QoS e prever o comportamento sob pressão de recursos.
> 2. Direcionar e repelir Pods com nodeSelector, taints e tolerations — incluindo o taint do control plane que você encontrou no Capítulo 6.
> 3. Usar affinity e anti-affinity para espalhar ou aproximar workloads.
> 4. Configurar o Horizontal Pod Autoscaler e explicar VPA e Cluster Autoscaler.
> 5. Proteger a disponibilidade durante manutenções com PodDisruptionBudgets.
> 6. Comparar e implementar estratégias de deploy: rolling, blue-green e canary.

> **Cenário do capítulo**: use o cluster de 3 nós do Capítulo 6 (com o metrics-server instalado — faremos isso na seção 7.2.1). Tudo também funciona no Minikube com `--nodes 3`.

---

## 7.1 Controle de alocação

Com um nó só, o scheduler não tinha escolhas. Com três, cada Pod novo dispara a pergunta do Capítulo 1: **em qual nó?** Esta seção apresenta as três alavancas que influenciam a resposta — da mais básica (quanto recurso preciso) à mais expressiva (com quem quero ou não quero conviver).

### 7.1.1 Requests e limits de recursos

Você já viu `resources` de passagem nos manifestos; agora, o significado preciso — porque **requests e limits fazem coisas completamente diferentes**:

```yaml
resources:
  requests:            # o que o Pod RESERVA — usado pelo SCHEDULER
    cpu: 250m          # 250 milicores = 0,25 CPU
    memory: 256Mi
  limits:              # o TETO — imposto pelo kubelet/kernel em tempo de execução
    cpu: 500m
    memory: 512Mi
```

- **Requests** são a moeda do **agendamento**: o scheduler soma os requests dos Pods de cada nó e só considera nós onde o novo Pod "cabe". *Não* é uso real — um Pod pode pedir 1 CPU e usar 0,1 (desperdício reservado) ou pedir 0,1 e usar 1 (estouro por conta e risco).
- **Limits** são o **teto em execução**, e o kernel os impõe de forma diferente por recurso:
  - **CPU é compressível**: estourou o limit → **throttling** (o processo desacelera, não morre).
  - **Memória é incompressível**: estourou o limit → **OOMKill** (o container é morto pelo kernel e o kubelet o reinicia — o motivo nº 1 de `OOMKilled` que você investigará no Capítulo 9).

**Classes de QoS** — o Kubernetes classifica cada Pod pela combinação request/limit, e usa isso para decidir **quem morre primeiro** quando um nó fica sem memória (evicção):

| Classe | Condição | Sob pressão do nó... |
|---|---|---|
| **Guaranteed** | requests = limits em tudo | último a ser despejado |
| **Burstable** | tem requests, limits maiores (ou ausentes) | intermediário |
| **BestEffort** | nada declarado | **primeiro a morrer** |

```bash
kubectl get pod <nome> -o jsonpath='{.status.qosClass}'
```

**Boas práticas destiladas (e debates reais do mercado):**

1. **Sempre declare requests.** Sem eles, o scheduler agenda às cegas e seus Pods são BestEffort — os primeiros sacrificados.
2. **Limit de memória: sempre** (um vazamento sem teto derruba o nó inteiro, levando os vizinhos junto).
3. **Limit de CPU: controverso.** Muitos times não o definem (throttling causa latência misteriosa); outros o exigem por previsibilidade multi-tenant. Para o curso: defina, e saiba medir o throttling antes de removê-lo.
4. Cargas críticas → **Guaranteed** (requests = limits).

**Governança por namespace** — fechando um gancho do Capítulo 3, os dois objetos que impõem disciplina:

```yaml
apiVersion: v1
kind: ResourceQuota            # teto AGREGADO do namespace
metadata: { name: quota-dev, namespace: dev }
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.memory: 16Gi
    pods: "30"
---
apiVersion: v1
kind: LimitRange               # padrões e faixas POR POD/CONTAINER
metadata: { name: padroes-dev, namespace: dev }
spec:
  limits:
  - type: Container
    default:        { cpu: 500m, memory: 256Mi }   # limit aplicado a quem não declara
    defaultRequest: { cpu: 100m, memory: 128Mi }   # request aplicado a quem não declara
```

> Detalhe importante: com ResourceQuota de requests/limits ativa, Pods **sem** declarações são *rejeitados* — a menos que um LimitRange forneça os padrões. Os dois andam juntos.

**Veja o inventário do seu cluster:**

```bash
kubectl describe node worker-1 | grep -A8 "Allocated resources"
# Requests somados vs. capacidade — a "contabilidade" que o scheduler consulta
```

### 7.1.2 Taints, tolerations e nodeSelector

**nodeSelector — atração simples.** O jeito mais direto de dizer "este Pod roda em nós com tal característica": labels no nó + selector no Pod.

```bash
kubectl label node worker-2 disktype=ssd
```

```yaml
spec:
  nodeSelector:
    disktype: ssd        # só agenda em nós com esta label
```

Casos típicos: nós com GPU, com SSD, de uma zona específica. Limite: é tudo-ou-nada e só *atrai* — não impede que *outros* Pods usem o nó. Para expressar preferências ou repulsão, veja 7.1.3 e os taints.

**Taints e tolerations — repulsão com exceções.** Inverte a lógica: em vez de o Pod escolher o nó, **o nó repele Pods**, salvo os que declaram tolerância. É a resposta ao mistério do Capítulo 6 (Teste 1: nada agendava no cp-1):

```bash
kubectl describe node cp-1 | grep Taints
# Taints: node-role.kubernetes.io/control-plane:NoSchedule
```

Anatomia de um taint — `chave=valor:efeito`, com três efeitos:

- **NoSchedule**: novos Pods sem tolerância não entram (os existentes ficam).
- **PreferNoSchedule**: versão branda — evite se possível.
- **NoExecute**: não entra **e** quem já está é **despejado** (após `tolerationSeconds`, se definido).

```bash
# Dedicar worker-2 a cargas de GPU:
kubectl taint node worker-2 dedicated=gpu:NoSchedule

# Remover um taint (repare no sufixo "-"):
kubectl taint node worker-2 dedicated=gpu:NoSchedule-
```

O Pod que *pode* entrar declara a tolerância (e note: tolerar **permite**, não obriga — para *garantir* que o Pod vá ao nó dedicado, combine taint + nodeSelector/affinity):

```yaml
spec:
  tolerations:
  - key: dedicated
    operator: Equal
    value: gpu
    effect: NoSchedule
  nodeSelector:
    dedicated: gpu       # (label correspondente que você aplicou ao nó)
```

**O segredo do Teste 5 do Capítulo 6, revelado.** Lembra dos ~5 minutos até os Pods do nó morto serem realocados? Quando um nó fica `NotReady`, o Kubernetes aplica a ele o taint `node.kubernetes.io/not-ready:NoExecute` — e **todo Pod carrega, por padrão, uma tolerância a esse taint com `tolerationSeconds: 300`**. Cinco minutos de tolerância antes do despejo. Cargas que precisam reagir mais rápido reduzem esse valor:

```yaml
tolerations:
- key: node.kubernetes.io/not-ready
  operator: Exists
  effect: NoExecute
  tolerationSeconds: 30      # despejo em 30s em vez de 300s
```

(É também assim que DaemonSets sobrevivem em nós com problemas: suas tolerâncias são generosas por design.)

### 7.1.3 Affinity e anti-affinity

A família *affinity* é a linguagem rica de posicionamento — com dois eixos:

**Eixo 1 — em relação a NÓS (node affinity):** o nodeSelector adulto, com operadores (`In`, `NotIn`, `Exists`, `Gt`...) e, crucialmente, **dois níveis de força**:

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:      # OBRIGATÓRIO (hard)
        nodeSelectorTerms:
        - matchExpressions:
          - { key: disktype, operator: In, values: [ssd, nvme] }
      preferredDuringSchedulingIgnoredDuringExecution:     # PREFERENCIAL (soft)
      - weight: 80
        preference:
          matchExpressions:
          - { key: topology.kubernetes.io/zone, operator: In, values: [zona-a] }
```

Leia os nomes compridos sem medo: *required...* = "sem isso, não agenda"; *preferred...* = "tente, mas não trave"; e *IgnoredDuringExecution* = a regra vale **na hora de agendar** — se a label do nó mudar depois, Pods rodando não são movidos.

**Eixo 2 — em relação a OUTROS PODS (pod affinity/anti-affinity):** posicionar considerando quem já está rodando. O parâmetro-chave é o **`topologyKey`**: o "domínio" da regra (mesmo nó = `kubernetes.io/hostname`; mesma zona = `topology.kubernetes.io/zone`).

O uso mais importante na prática — **anti-affinity para espalhar réplicas** (a resposta a uma pergunta aberta desde o Capítulo 1: como evitar que réplicas caiam juntas?):

```yaml
spec:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels: { app: api }
        topologyKey: kubernetes.io/hostname     # NUNCA duas réplicas no mesmo nó
```

E o irmão de atração — **pod affinity para aproximar** (ex.: cache junto da API que o consome, na mesma zona, cortando latência):

```yaml
    podAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels: { app: api }
          topologyKey: topology.kubernetes.io/zone
```

> **Armadilha clássica**: anti-affinity `required` por hostname com `replicas: 4` num cluster de 2 workers = a 3ª e 4ª réplicas ficam **Pending para sempre** (não há nó válido). Regra de bolso: `required` só quando a violação for inaceitável; para "espalhe o melhor possível", prefira `preferred` — ou o mecanismo moderno e mais simples para esse fim, **`topologySpreadConstraints`**, que declara o desvio máximo de réplicas por domínio (`maxSkew`) e é hoje a recomendação padrão para distribuição uniforme.

**Exercício de fixação 7.1**
1. Um Pod pede `memory request: 256Mi, limit: 256Mi` e outro não declara nada. Classifique o QoS de cada um e diga quem é despejado primeiro sob pressão de memória.
2. Estourar o limit de CPU e o de memória têm consequências diferentes. Quais, e por que essa assimetria existe?
3. Com taint + toleration apenas, um nó "dedicado a GPU" ainda pode ficar ocioso ou receber o workload errado. Explique os dois problemas e a configuração completa que os resolve.
4. Explique os ~5 minutos do Teste 5 (Capítulo 6) em termos de taints e tolerationSeconds — e como reduzi-los para uma carga crítica.
5. Escreva a regra que garante: réplicas do Deployment `pagamentos` nunca no mesmo nó, e de preferência distribuídas entre zonas. Que risco o "nunca" embute?

---

## 7.2 Escalabilidade

Alocar bem é estático; a demanda não é. Os três autoscalers do ecossistema atacam eixos diferentes — memorize pela pergunta que cada um responde:

```
HPA  →  "preciso de MAIS RÉPLICAS?"        (escala horizontal de Pods)
VPA  →  "cada réplica precisa de MAIS RECURSO?" (escala vertical de Pods)
CA   →  "preciso de MAIS NÓS?"             (escala do cluster)
```

### 7.2.1 Horizontal Pod Autoscaler (HPA)

O HPA ajusta `replicas` de um Deployment/StatefulSet para perseguir um alvo de utilização — o loop de reconciliação (Capítulo 1) aplicado à escala:

```
a cada 15s:  métrica atual ─▶ compara com alvo ─▶ réplicas = teto(atuais × atual/alvo)
```

Exemplo do cálculo: 3 réplicas a 90% de CPU com alvo de 50% → `teto(3 × 90/50) = 6` réplicas.

**Pré-requisito 1 — metrics-server** (a fonte das métricas de CPU/memória; seu cluster kubeadm não o tem):

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# Em lab com certificados autoassinados nos kubelets, adicione ao container do
# metrics-server o argumento: --kubelet-insecure-tls (somente em lab!)
kubectl top nodes && kubectl top pods -A      # funcionou? então o HPA tem o que comer
```

**Pré-requisito 2 — requests declarados** no workload: "% de utilização" do HPA é **percentual do request** (7.1.1). Sem request, o HPA não tem denominador e falha.

**Mãos à obra:**

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60        # alvo: média de 60% dos requests
  behavior:                           # amortecimento (evita "flapping")
    scaleDown:
      stabilizationWindowSeconds: 300 # só reduz após 5 min de folga sustentada
```

**Laboratório — assista à escala acontecer:**

```bash
kubectl create deploy api --image=registry.k8s.io/hpa-example --replicas=2
kubectl set resources deploy api --requests=cpu=100m,memory=64Mi --limits=cpu=200m,memory=128Mi
kubectl expose deploy api --port=80
kubectl apply -f hpa.yaml
kubectl get hpa -w &                  # acompanhe TARGETS e REPLICAS

# Gere carga (o hpa-example queima CPU a cada requisição):
kubectl run gerador --rm -it --image=busybox:1.36 -- \
  sh -c 'while true; do wget -qO- http://api >/dev/null; done'
# TARGETS sobe (200%+/60%), REPLICAS: 2 → 4 → 7... Ctrl+C no gerador:
# a carga cai na hora; as réplicas, só após a janela de estabilização. Por design.
```

> **Além de CPU**: o `autoscaling/v2` aceita memória, múltiplas métricas (vale a que pedir mais réplicas) e métricas **customizadas/externas** — requisições/s, lag de fila Kafka... Para eventos e "escala até zero", o padrão de mercado é o **KEDA** (mais um Operator para a coleção do Capítulo 10).

### 7.2.2 Vertical Pod Autoscaler (visão geral)

O VPA ataca o outro eixo: em vez de mais réplicas, **ajusta requests/limits** de cada Pod com base no consumo observado. Componente à parte (não vem no cluster), com três modos:

- **`Off`** — só **recomenda** (grava valores sugeridos no status, sem tocar em nada). *O modo mais usado na prática*: uma resposta baseada em dados para a eterna pergunta "quanto request eu coloco?" da seção 7.1.1.
- **`Initial`** — aplica a recomendação só na criação do Pod.
- **`Auto`** — aplica continuamente. Ressalva histórica: aplicar exigia **recriar o Pod** (disrupção!); o redimensionamento *in-place* (sem restart) amadureceu nas versões recentes do Kubernetes e muda esse cenário — verifique o estado na sua versão.

**Regras de convivência**: VPA `Auto` + HPA sobre a **mesma métrica** (CPU) = briga — um muda o denominador que o outro usa. Combinação segura e comum: **HPA em CPU/custom + VPA em modo recomendação** (ou VPA só de memória).

Quando VPA brilha: workloads que não escalam horizontalmente (aquele monólito, um banco) e o combate sistemático ao **superdimensionamento** — em escala, requests gordos demais significam nós ociosos pagos.

### 7.2.3 Cluster Autoscaler (conceito)

Terceiro eixo: HPA pediu 10 réplicas, mas **não há nó onde caibam** — Pods `Pending` com evento `Insufficient cpu`. O **Cluster Autoscaler (CA)** observa exatamente isso e age no nível da infraestrutura:

- **Scale-up**: Pods Pending por falta de recursos → cria nós (via API da nuvem: ASG/MIG/VMSS) → o Pod agenda (lembre: nó novo entra no cluster pelo mesmíssimo fluxo de join do Capítulo 6, só que automatizado).
- **Scale-down**: nó subutilizado (padrão: <50% por ~10 min) e cujos Pods cabem alhures → **drain gracioso** (o do Capítulo 6.4.1, respeitando PDBs da seção 7.3.1!) → remove o nó.

Pontos de atenção conceituais:

- O CA raciocina por **requests, não uso real** — mais um motivo para requests honestos (o tema que costura este capítulo).
- Certas cargas "prendem" nós no scale-down: Pods com storage local, sem controller, ou protegidos por PDB apertado — comportamento configurável por annotations.
- Em **bare metal** (nosso cluster do Capítulo 6) não há API para criar máquinas — o "autoscaler" é você com o runbook 6.4.4. Nas nuvens gerenciadas (6.3.3), o CA é praticamente item de série; o projeto **Karpenter** (AWS, expandindo) é a evolução: provisiona nós sob medida para os Pods pendentes, sem grupos fixos.

**A cadeia completa da elasticidade**, que é o desenho para guardar:

```
tráfego sobe → HPA cria réplicas → réplicas não cabem (Pending)
            → CA cria nós → scheduler aloca → tráfego cai
            → HPA reduz réplicas → nós esvaziam → CA drena e remove nós
```

**Exercício de fixação 7.2**
1. HPA com alvo de 50% de CPU; 4 réplicas rodando a 75%. Quantas réplicas ele pedirá? Mostre a conta.
2. Por que o HPA de utilização não funciona em Pods sem requests? O que exatamente o "60%" referencia?
3. Sua fila Kafka acumula mensagens à noite, quando a CPU está baixa. Por que o HPA de CPU falha aqui e que caminho você adotaria?
4. Explique o conflito VPA(Auto)+HPA na mesma métrica e proponha uma combinação segura para uma API com picos.
5. Um Pod está Pending com `Insufficient memory` no cluster on-prem do Capítulo 6. O que o CA faria na nuvem, e qual é o seu runbook manual equivalente?

---

## 7.3 Resiliência

Escalar trata da demanda; resiliência trata das **disrupções** — e o Kubernetes as divide em involuntárias (nó morre — Teste 5, mitigado por réplicas + anti-affinity) e **voluntárias** (drain, upgrade, deploy). As voluntárias são as mais frequentes... e as mais controláveis.

### 7.3.1 PodDisruptionBudgets

Cenário-pesadelo: `pagamentos` tem 3 réplicas; um colega roda `kubectl drain` num nó, o autoscaler decide encolher outro ao mesmo tempo → 2 réplicas despejadas juntas → sobra 1 → pico → incidente. Cada ação era legítima; a **combinação** foi fatal.

O **PodDisruptionBudget (PDB)** é o contrato que impede isso — "quantos Pods deste conjunto podem estar indisponíveis por disrupção **voluntária**":

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: pagamentos-pdb
spec:
  minAvailable: 2              # OU maxUnavailable: 1 (escolha um)
  selector:
    matchLabels:
      app: pagamentos
```

Mecânica: drain (6.4.1) e amigos usam a **Eviction API**, que consulta o PDB antes de cada despejo. Violaria o orçamento? O despejo é **negado** e o drain espera/tenta de novo — tipicamente até o controller repor a réplica em outro nó, quando então o próximo despejo é liberado. O drain fica mais lento e **é esse o objetivo**: velocidade de manutenção trocada por disponibilidade.

O que o PDB **não** faz — tão importante quanto:

- **Não protege de disrupções involuntárias** (nó que explode não pede licença) — para essas, réplicas + anti-affinity (7.1.3).
- **Não cria réplicas**: `minAvailable: 2` com `replicas: 2` = **nenhum** despejo voluntário permitido → drains e upgrades de nó **travam** (o CA inclusive respeita e não remove o nó). PDB coerente com o número de réplicas é requisito, não detalhe.
- Percentuais são válidos (`minAvailable: "80%"`) e convivem melhor com HPA mudando o total de réplicas.

```bash
kubectl get pdb
# NAME             MIN AVAILABLE   ALLOWED DISRUPTIONS   ← o campo que o drain consulta
# pagamentos-pdb   2               1
```

**Teste você mesmo** (cluster do Capítulo 6): crie o Deployment com 3 réplicas + o PDB acima, force as 3 réplicas para 2 nós e drene um deles observando `kubectl get pods -w` — os despejos saem **um por vez**, esperando a reposição.

### 7.3.2 Estratégias de deploy: rolling, blue-green, canary

Deploy é a disrupção voluntária mais frequente de todas. Três estratégias, três trocas diferentes entre **custo, risco e velocidade de rollback**:

**Rolling update — o nativo (Capítulo 3, agora com olhos de resiliência).**
Substituição gradual, governada por `maxSurge`/`maxUnavailable` + readiness. Barato (sem infra extra) e automático.
Limites que motivam as outras estratégias: durante a janela, **v1 e v2 coexistem** (exige compatibilidade de API/esquema de banco entre versões consecutivas — disciplina de engenharia, não de YAML); o rollback é rápido (`rollout undo`), mas não instantâneo; e não há como testar v2 com tráfego real *antes* de os usuários a receberem.

**Blue-green — troca atômica.**
Dois ambientes completos: **blue** (v1, ativo) e **green** (v2, em standby). Testa-se o green à vontade (smoke tests via um Service interno próprio) e então **vira-se a chave** — no Kubernetes puro, a chave é o **selector do Service** (eis os labels do Capítulo 3 no seu papel mais dramático):

```yaml
# Deployments "web-blue" (labels app: web, slot: blue) e "web-green" (slot: green)
kind: Service
spec:
  selector:
    app: web
    slot: blue        # ← v2 no ar = trocar para "green" e aplicar. Rollback = voltar.
```

Corte instantâneo (sem coexistência de versões para os usuários) e rollback em segundos — ao custo de **2× a infraestrutura** durante a transição e do cuidado com o que é compartilhado (o banco é um só: migrações precisam ser compatíveis com ambas as versões — o padrão *expand/contract*).

**Canary — exposição progressiva.**
A v2 recebe primeiro uma **fração** do tráfego real (5%...), monitora-se (erros, latência — Capítulo 9 dará os olhos), e amplia-se por etapas até 100% — ou aborta-se ao primeiro sinal ruim, com raio de dano limitado a poucos usuários.
No Kubernetes puro, a aproximação é grosseira — dois Deployments sob o mesmo Service, com a proporção ditada pelo nº de réplicas (1 canary : 9 estáveis ≈ 10%):

```
Service (app: web) ──▶ web-stable  (réplicas: 9, versão v1)
                   └─▶ web-canary  (réplicas: 1, versão v2)
```

Controle fino (percentuais exatos, por header/cookie, análise automática de métricas com promoção/abort) vem das ferramentas de cima: pesos no **Ingress** (annotations de canary do Ingress-NGINX), **Argo Rollouts**/**Flagger** (progressive delivery declarativa — primos do GitOps do Capítulo 11) ou service mesh.

**Quadro de decisão:**

| | Rolling | Blue-green | Canary |
|---|---|---|---|
| Custo extra | ~zero | 2× na transição | pequeno |
| Coexistência v1/v2 | sim, na janela | não (corte atômico) | sim, prolongada e proposital |
| Rollback | rápido | **instantâneo** | instantâneo (na fração) |
| Risco ao usuário | médio | médio (tudo troca de uma vez) | **mínimo e controlado** |
| Complexidade | baixa | média | média/alta (exige métricas!) |
| Quando | padrão geral | releases "tudo-ou-nada", janelas de corte | mudanças arriscadas, alto tráfego |

E as três dependem do mesmo alicerce, plantado nos capítulos anteriores: **readiness probes honestas** (Capítulo 3), **graceful shutdown** via SIGTERM (Capítulo 1) e **PDBs** protegendo o processo (7.3.1). Estratégia sofisticada sobre probes ruins é teatro.

**Exercício de fixação 7.3**
1. Por que um PDB não teria ajudado no Teste 5 do Capítulo 6, mas é decisivo durante o upgrade do 6.4.2?
2. `replicas: 2` + `minAvailable: 2`: descreva as duas consequências operacionais (uma no drain, outra no Cluster Autoscaler).
3. Sua v2 muda uma coluna do banco. Explique o risco no rolling update e como o padrão expand/contract o elimina (vale para blue-green também).
4. Monte o esqueleto YAML de um canary a 25% "no Kubernetes puro" para o app `web`. Qual é a limitação de precisão e que ferramenta a resolveria?
5. Para cada cenário, escolha a estratégia e justifique: (a) hotfix simples numa API interna; (b) migração de gateway de pagamento na Black Friday; (c) novo algoritmo de recomendação com risco desconhecido.

---

## Laboratório consolidado do capítulo

No cluster de 3 nós do Capítulo 6 (~45 min):

```bash
# 0. Pré-requisito
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# (ajuste --kubelet-insecure-tls se necessário) e valide: kubectl top nodes

kubectl create namespace lab7 && kubectl config set-context --current --namespace=lab7

# 1. QoS na prática
kubectl run melhor-esforco --image=nginx:1.27
kubectl run garantido --image=nginx:1.27 \
  --overrides='{"spec":{"containers":[{"name":"garantido","image":"nginx:1.27","resources":{"requests":{"cpu":"100m","memory":"128Mi"},"limits":{"cpu":"100m","memory":"128Mi"}}}]}}'
kubectl get pod melhor-esforco garantido -o custom-columns=NOME:.metadata.name,QOS:.status.qosClass

# 2. OOMKill controlado (memória é incompressível!)
kubectl run estourado --image=polinux/stress --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"estourado","image":"polinux/stress","resources":{"limits":{"memory":"64Mi"}},"command":["stress","--vm","1","--vm-bytes","128M"]}]}}'
kubectl get pod estourado -w              # OOMKilled; Ctrl+C. describe confirma a razão.

# 3. Taint e toleration
kubectl taint node worker-2 dedicated=especial:NoSchedule
kubectl create deploy comum --image=nginx:1.27 --replicas=4
kubectl get pods -o wide                  # nada no worker-2
kubectl taint node worker-2 dedicated=especial:NoSchedule-   # limpe ao final

# 4. Anti-affinity espalhando réplicas
kubectl create deploy espalhado --image=nginx:1.27 --replicas=2 --dry-run=client -o yaml > esp.yaml
# (edite: adicione podAntiAffinity required por kubernetes.io/hostname, label app: espalhado)
kubectl apply -f esp.yaml && kubectl get pods -o wide        # um por nó
kubectl scale deploy espalhado --replicas=4
kubectl get pods                          # a 4ª fica Pending — a armadilha do required, ao vivo
kubectl describe pod <pendente> | grep -A3 Events            # leia a explicação do scheduler

# 5. HPA de ponta a ponta (roteiro da seção 7.2.1)
#    deploy hpa-example + requests + service + hpa + gerador de carga → observe subir e descer

# 6. PDB segurando um drain
kubectl create deploy pago --image=nginx:1.27 --replicas=3
kubectl create pdb pago-pdb --selector=app=pago --min-available=2
kubectl drain worker-1 --ignore-daemonsets --delete-emptydir-data &
kubectl get pods -w                       # despejos de um em um, aguardando reposição
kubectl uncordon worker-1

# 7. Blue-green manual
kubectl create deploy web-blue --image=nginxdemos/hello:plain-text
kubectl create deploy web-green --image=nginxdemos/hello:plain-text
kubectl label deploy web-blue slot=blue && kubectl label deploy web-green slot=green
# (garanta as labels slot também nos templates dos Pods; crie o Service com selector slot: blue)
# teste, edite o selector para green, aplique: corte atômico. Volte: rollback instantâneo.

# 8. Limpeza
kubectl delete namespace lab7
kubectl config set-context --current --namespace=default
```

---

## Resumo do capítulo

- **Requests** guiam o scheduler (reserva); **limits** governam a execução — CPU estourada é *throttled*, memória estourada é *OOMKilled*. A combinação define o **QoS** (Guaranteed > Burstable > BestEffort) e a ordem de sacrifício sob pressão. **ResourceQuota + LimitRange** disciplinam namespaces.
- **nodeSelector** atrai (simples); **taints/tolerations** repelem com exceções (NoSchedule/PreferNoSchedule/NoExecute) — incluindo o taint do control plane e o mecanismo not-ready+`tolerationSeconds` por trás dos "5 minutos" da falha de nó. **Affinity/anti-affinity** expressam required/preferred sobre nós e sobre Pods (`topologyKey`); anti-affinity espalha réplicas — com `required`, cuidado com o Pending eterno (prefira `preferred` ou `topologySpreadConstraints`).
- Elasticidade em três eixos: **HPA** (réplicas, sobre % dos *requests*, via metrics-server, com janela de estabilização), **VPA** (requests certos — modo recomendação é o porto seguro; cuidado ao combinar com HPA na mesma métrica) e **Cluster Autoscaler** (nós, guiado por Pods Pending; drena com respeito a PDBs; em bare metal, o autoscaler é você).
- **PDBs** limitam disrupções **voluntárias** (drain, upgrade, CA) negando evictions que violem o orçamento — e precisam ser coerentes com o nº de réplicas para não travar a operação.
- Deploys: **rolling** (padrão, coexistência de versões), **blue-green** (corte e rollback atômicos, 2× custo), **canary** (risco mínimo, exige métricas; controle fino com Ingress/Argo Rollouts/Flagger) — todos sustentados por readiness, graceful shutdown e PDBs.

**Ponte para o Capítulo 8**: o cluster agora aloca com critério, escala sozinho e sobrevive a manutenções — mas qualquer pessoa com o kubeconfig ainda pode tudo, qualquer Pod fala com qualquer Pod, e há senhas em base64 no etcd. Chegou a hora de trancar as portas: ServiceAccounts, RBAC, SecurityContext e NetworkPolicies.
