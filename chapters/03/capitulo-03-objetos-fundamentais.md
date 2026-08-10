# Capítulo 3 — Objetos fundamentais

> **Objetivos de aprendizagem**
> Ao final deste capítulo, você será capaz de:
> 1. Descrever a anatomia de um Pod, seu ciclo de vida e por que ele — e não o container — é a unidade mínima do Kubernetes.
> 2. Explicar quando usar Pods multi-container e o padrão sidecar.
> 3. Configurar probes de liveness, readiness e startup, e explicar o que acontece quando cada uma falha.
> 4. Explicar a cadeia Deployment → ReplicaSet → Pod e executar rolling updates e rollbacks.
> 5. Identificar quando usar DaemonSet, StatefulSet, Job e CronJob.
> 6. Organizar recursos com namespaces e dominar labels, selectors e annotations.

---

## 3.1 Pods

### 3.1.1 Anatomia de um Pod e ciclo de vida

**Por que Pod, e não container?**
O Kubernetes não agenda containers individualmente. Sua menor unidade de implantação é o **Pod**: um envelope que contém **um ou mais containers** que compartilham:

- **Namespace de rede**: todos os containers do Pod têm o **mesmo IP** e o mesmo espaço de portas, e se falam via `localhost`.
- **Volumes**: diretórios que podem ser montados por todos os containers do Pod.
- **Destino**: os containers de um Pod são sempre agendados **juntos, no mesmo nó**, e vivem e morrem juntos.

Na prática, a regra é **um container de aplicação por Pod** — os containers extras, quando existem, são auxiliares (seção 3.1.2). A analogia útil: o Pod é uma "máquina lógica" mínima, e os containers são os processos dela.

**Anatomia em YAML:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: api
  labels:
    app: api
spec:
  containers:
  - name: app
    image: registry.exemplo.com/loja/api:2.4.1
    ports:
    - containerPort: 8080
    env:
    - name: LOG_LEVEL
      value: "info"
    resources:              # Capítulo 7 aprofunda
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        memory: 256Mi
  restartPolicy: Always     # Always | OnFailure | Never
```

**Detalhe de bastidor que explica o compartilhamento**: em cada Pod, o Kubernetes cria um container invisível, o **pause container**, cujo único trabalho é "segurar" os namespaces de rede que os demais containers do Pod entram e compartilham. Você pode vê-lo listando os containers direto no containerd do nó.

**Ciclo de vida (fases do Pod):**

```
Pending ──▶ Running ──▶ Succeeded (todos os containers terminaram com exit 0)
   │            └─────▶ Failed    (algum terminou com erro e não será reiniciado)
   └──▶ (Unknown: nó incomunicável)
```

- **Pending**: aceito pelo API server, mas ainda não está com todos os containers rodando — pode estar aguardando o scheduler, o download da imagem ou a montagem de volumes. *Pods presos em Pending geralmente indicam falta de recursos ou problema de imagem — os Events do `describe` (Capítulo 2) contam a história.*
- **Running**: vinculado a um nó, com ao menos um container em execução.
- **Succeeded/Failed**: fases terminais — relevantes para Jobs (seção 3.2.3).

Além da fase, cada container tem seu próprio estado (`Waiting`, `Running`, `Terminated`) e um **contador de restarts**. Quando um container falha repetidamente, o kubelet reinicia com intervalos crescentes (10s, 20s, 40s... até 5 min) — é o famoso **CrashLoopBackOff**, que você aprenderá a depurar no Capítulo 9.

**Dois fatos essenciais sobre Pods:**

1. **Pods são efêmeros e descartáveis.** Um Pod nunca é "movido" de nó nem "recriado" pelo sistema — se morre, morre; algo (um controller) cria *outro* no lugar, com novo nome e novo IP.
2. **Você quase nunca cria Pods diretamente.** Um Pod "avulso" não tem self-healing: se o nó cair, ninguém o recria. Por isso o uso real é sempre via controladores (seção 3.2) — o Pod avulso serve para testes e depuração.

### 3.1.2 Multi-container Pods e sidecars

Quando faz sentido colocar mais de um container no mesmo Pod? Quando os processos são **fortemente acoplados**: precisam compartilhar rede/arquivos e escalar juntos. Os padrões clássicos:

- **Sidecar**: um container auxiliar que complementa o principal. Exemplos: um agente que coleta logs de um volume compartilhado e os envia para um sistema central; um proxy que cifra o tráfego (base dos service meshes, como Istio/Linkerd); um sincronizador que baixa conteúdo periodicamente para o servidor web servir.
- **Ambassador**: um proxy local que simplifica o acesso do app a serviços externos (o app fala com `localhost`, o ambassador resolve o resto).
- **Adapter**: traduz a saída do app para um formato padrão (ex.: expor métricas no formato Prometheus).

**Init containers** — um mecanismo relacionado e muito usado: containers que rodam **antes** dos containers principais, **em sequência, até o fim**. Servem para preparação: aguardar um banco ficar disponível, rodar migrações, baixar configuração.

```yaml
spec:
  initContainers:
  - name: espera-banco
    image: busybox:1.36
    command: ['sh', '-c', 'until nc -z db 5432; do echo aguardando db; sleep 2; done']
  containers:
  - name: app
    image: loja/api:2.4.1
  - name: log-shipper          # sidecar
    image: fluent-bit:3.1
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
  volumes:
  - name: logs
    emptyDir: {}
```

> **Nota de versão**: desde o Kubernetes 1.29, existe o *sidecar nativo* — um init container com `restartPolicy: Always`, que inicia antes do app, continua rodando junto e termina depois dele. Resolve antigos problemas de ordem de inicialização/encerramento de sidecars.

**Anti-padrão para fixar**: colocar frontend e backend no mesmo Pod. Eles não precisam compartilhar rede local, e você perderia a capacidade de escalá-los independentemente. Acoplamento forte → mesmo Pod; comunicação via rede → Pods separados + Service (Capítulo 4).

### 3.1.3 Probes: liveness, readiness, startup

Como o kubelet sabe se sua aplicação está *realmente* bem? Processo rodando não significa aplicação saudável (pode estar em deadlock, sem conexão com o banco, ainda aquecendo). As **probes** são verificações periódicas que o kubelet executa em cada container:

**Mecanismos de verificação (os três servem para qualquer probe):**

- `httpGet`: sucesso = resposta HTTP 2xx/3xx em um caminho (ex.: `/healthz`).
- `tcpSocket`: sucesso = porta aceita conexão.
- `exec`: sucesso = comando dentro do container retorna exit 0.
- (`grpc`: para serviços gRPC com health checking padrão.)

**Os três tipos de probe e suas consequências:**

| Probe | Pergunta | Se falhar... |
|---|---|---|
| **liveness** | "Está vivo?" | O container é **reiniciado** |
| **readiness** | "Pode receber tráfego?" | O Pod é **removido dos endpoints do Service** (sem restart) |
| **startup** | "Já terminou de subir?" | Segura as outras probes; estourou o limite → **reinicia** |

```yaml
containers:
- name: app
  image: loja/api:2.4.1
  startupProbe:              # protege apps de inicialização lenta
    httpGet: { path: /healthz, port: 8080 }
    failureThreshold: 30     # até 30 × 5s = 150s para subir
    periodSeconds: 5
  livenessProbe:             # detecta travamentos
    httpGet: { path: /healthz, port: 8080 }
    periodSeconds: 10
    failureThreshold: 3      # 3 falhas seguidas → restart
  readinessProbe:            # controla o tráfego
    httpGet: { path: /ready, port: 8080 }
    periodSeconds: 5
```

**Como pensar cada uma:**

- **Liveness** deve testar só o que um **restart resolve** (deadlock, processo zumbi). *Não* inclua dependências externas: se o banco cair e a liveness testar o banco, o Kubernetes reiniciará todos os seus Pods em loop — sem resolver nada e piorando a situação.
- **Readiness** é o lugar das dependências: "consigo atender uma requisição agora?" Se o banco caiu, o Pod fica fora do balanceamento até o banco voltar — sem restarts inúteis. É também a peça-chave do **deploy sem downtime**: um Pod novo só recebe tráfego quando estiver pronto.
- **Startup** existe para aplicações lentas para subir (JVMs, por exemplo): sem ela, a liveness mataria o container antes de ele terminar o boot.

**Exercício de fixação 3.1**
1. Dois containers no mesmo Pod podem se comunicar via `localhost`. Por quê? Que componente "invisível" sustenta isso?
2. Cite dois motivos pelos quais criar Pods avulsos (sem controller) é má prática em produção.
3. Uma API demora 90s para iniciar e depende de um banco externo. Monte a estratégia de probes: o que vai na startup, na liveness e na readiness — e o que **não** deve ir na liveness?
4. Qual a diferença prática entre falhar a liveness e falhar a readiness?

---

## 3.2 Controladores de workload

No Capítulo 1 você aprendeu o loop de reconciliação; no 3.1, que Pods são descartáveis. Os **controladores de workload** unem as duas ideias: são objetos que declaram "quantos Pods, de que tipo, devem existir" — e loops de reconciliação garantem isso continuamente.

### 3.2.1 ReplicaSet

O ReplicaSet tem uma única missão: **manter N réplicas de um Pod rodando**.

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: web-rs
spec:
  replicas: 3
  selector:                 # COMO o RS encontra "seus" Pods
    matchLabels:
      app: web
  template:                 # o MOLDE dos Pods que ele cria
    metadata:
      labels:
        app: web            # deve casar com o selector!
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
```

Repare na estrutura — ela se repete em quase todos os workloads:

- **`replicas`**: o estado desejado.
- **`selector`**: o ReplicaSet **não guarda uma lista de Pods**; ele *conta*, a cada instante, quantos Pods casam com o selector. Menos que o desejado → cria pelo template; mais → deleta o excedente.
- **`template`**: um Pod completo embutido (tudo da seção 3.1 vale aqui dentro).

**Experimento revelador**: crie o RS acima, delete um Pod (`kubectl delete pod web-rs-xxxxx`) e rode `kubectl get pods -w` — um substituto nasce em segundos. Agora rode `kubectl scale rs web-rs --replicas=5`. É o loop de reconciliação, visível.

**Mas há um limite**: mude a imagem no template do ReplicaSet e... nada acontece com os Pods existentes. O RS só olha *quantidade*, não *versão*. Atualizar exigiria matar os Pods manualmente. É exatamente essa lacuna que o Deployment preenche — e por isso **você raramente cria ReplicaSets diretamente**.

### 3.2.2 Deployment (rolling update e rollback)

O **Deployment** gerencia ReplicaSets, adicionando o que falta: **atualizações declarativas com histórico**. A cadeia completa:

```
Deployment ──gerencia──▶ ReplicaSet(s) ──gerencia──▶ Pods
```

Quando você altera o template de um Deployment (nova imagem, nova env), ele:

1. Cria um **novo ReplicaSet** com o novo template (réplicas = 0);
2. **Escala gradualmente**: novo RS sobe, RS antigo desce, respeitando a readiness dos Pods novos;
3. Mantém o RS antigo **zerado, mas vivo** — ele é o histórico que permite rollback.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 4
  strategy:
    type: RollingUpdate         # padrão (a alternativa é Recreate: mata tudo, sobe tudo)
    rollingUpdate:
      maxSurge: 1               # até 1 Pod ACIMA do desejado durante o update
      maxUnavailable: 1         # até 1 Pod a menos que o desejado
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        readinessProbe:                    # sem readiness, "rolling" perde a graça:
          httpGet: { path: /, port: 80 }   # o K8s consideraria pronto qualquer container Running
```

**Laboratório de rolling update e rollback:**

```bash
kubectl apply -f web.yaml
kubectl rollout status deploy/web            # aguarda a implantação concluir

# Atualize a versão (na vida real: edite o YAML e apply; aqui, o atalho imperativo)
kubectl set image deploy/web nginx=nginx:1.28
kubectl rollout status deploy/web            # observe a troca gradual
kubectl get rs                               # DOIS ReplicaSets: novo=4, antigo=0

# Simule um desastre: versão inexistente
kubectl set image deploy/web nginx=nginx:1.99-inexistente
kubectl get pods                             # ImagePullBackOff nos novos...
# ...mas repare: os Pods antigos continuam servindo! (maxUnavailable limitou o estrago)

# Histórico e rollback
kubectl rollout history deploy/web
kubectl rollout undo deploy/web              # volta à revisão anterior
kubectl rollout undo deploy/web --to-revision=1   # ou a uma específica
kubectl rollout status deploy/web
```

> **Dica profissional**: use `kubectl annotate deploy/web kubernetes.io/change-cause="upgrade nginx 1.28"` (ou o campo equivalente no YAML) para que o `rollout history` mostre *o porquê* de cada revisão. E lembre-se da regra do Capítulo 2: o `set image` é ótimo para aprender e para emergências; no fluxo normal, a mudança nasce no YAML versionado no Git.

**Deployment é o workload padrão** para aplicações **stateless** (APIs, frontends, workers) — a imensa maioria do que roda em um cluster.

### 3.2.3 DaemonSet, StatefulSet e Job/CronJob (visão geral)

Nem todo workload é "N réplicas intercambiáveis". Os outros quatro controladores cobrem os demais formatos:

**DaemonSet — "um Pod em cada nó"**
Garante que **cada nó** (ou cada nó que case com um seletor) rode **exatamente uma cópia** do Pod. Quando um nó novo entra no cluster (Capítulo 6), o DaemonSet o povoa automaticamente.
*Usos típicos*: agentes de log (Fluent Bit), de métricas (node-exporter), de rede/CNI e de segurança. Você já viu um sem saber: o `kube-proxy` do Capítulo 2 é um DaemonSet — confirme com `kubectl get ds -n kube-system`.

**StatefulSet — identidade e ordem**
Para aplicações **com estado** (bancos, filas, sistemas distribuídos), onde as réplicas **não são intercambiáveis**. Diferenças em relação ao Deployment:

- Nomes **estáveis e ordinais**: `db-0`, `db-1`, `db-2` (e DNS estável para cada um).
- Cada réplica ganha **seu próprio volume persistente**, que sobrevive a restarts e a recriações do Pod (`volumeClaimTemplates`).
- Criação, atualização e remoção em **ordem** (0 → 1 → 2 para subir; inverso para descer).

*Usos típicos*: PostgreSQL, MySQL, Kafka, Redis com persistência. O Capítulo 5 traz um laboratório completo com banco de dados; por ora, guarde o critério: **réplicas trocáveis → Deployment; réplicas com identidade/disco próprio → StatefulSet**.

**Job — "rode até concluir"**
Cria Pods para executar uma tarefa **finita** e garante que ela termine com sucesso (reexecutando em caso de falha, até `backoffLimit`). Suporta paralelismo (`completions`, `parallelism`).
*Usos típicos*: migração de banco, processamento em lote, renderização.

```yaml
apiVersion: batch/v1
kind: Job
metadata: { name: migracao }
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: OnFailure      # Jobs usam OnFailure ou Never (nunca Always)
      containers:
      - name: migrate
        image: loja/api:2.4.1
        command: ["./migrate.sh"]
```

**CronJob — Jobs agendados**
Cria Jobs em um cronograma no formato cron clássico:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata: { name: backup-diario }
spec:
  schedule: "0 3 * * *"             # todo dia às 03:00
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: loja/backup:1.0
```

*Usos típicos*: backups, relatórios, limpezas periódicas.

**Mapa de decisão:**

```
Que tipo de trabalho?
├─ Serviço contínuo, réplicas intercambiáveis ───────▶ Deployment
├─ Serviço contínuo, com identidade/estado por réplica ▶ StatefulSet
├─ Um agente por nó ─────────────────────────────────▶ DaemonSet
├─ Tarefa que termina ───────────────────────────────▶ Job
└─ Tarefa que termina, em horários programados ──────▶ CronJob
```

**Exercício de fixação 3.2**
1. Por que atualizar a imagem no template de um ReplicaSet não muda os Pods existentes, mas no Deployment sim? O que o Deployment cria por baixo?
2. Durante um rolling update com `replicas: 4`, `maxSurge: 1` e `maxUnavailable: 1`, quantos Pods podem existir no máximo e no mínimo em dado instante?
3. Escolha o controlador certo: (a) coletor de métricas em todos os nós; (b) cluster Kafka de 3 brokers; (c) reprocessamento noturno de pedidos; (d) API REST stateless.
4. Por que um Job não pode usar `restartPolicy: Always`?

---

## 3.3 Namespaces

### 3.3.1 Organização lógica de recursos

**Namespaces** dividem um cluster físico em espaços lógicos — como "pastas" para recursos. Servem para:

- **Organização**: separar times, projetos ou ambientes (`dev`, `homolog`, `prod`) no mesmo cluster.
- **Escopo de nomes**: dois Deployments chamados `web` podem coexistir, um em cada namespace.
- **Fronteira de políticas**: RBAC (quem pode fazer o quê — Capítulo 8), quotas de recursos (`ResourceQuota`, `LimitRange` — Capítulo 7) e isolamento de rede (`NetworkPolicy` — Capítulo 8) são aplicados **por namespace**.

```bash
kubectl get namespaces
```
```
default           # onde caem recursos sem namespace explícito
kube-system       # componentes do próprio Kubernetes (Capítulo 2)
kube-public       # leitura pública (pouco usado)
kube-node-lease   # heartbeats dos nós
```

**Criando e usando:**

```bash
kubectl create namespace loja-dev            # (em produção: via YAML versionado)
kubectl apply -f web.yaml -n loja-dev        # aplica no namespace
kubectl get pods -n loja-dev                 # consulta no namespace
kubectl config set-context --current --namespace=loja-dev   # muda o padrão do contexto
kubectl get pods -A                          # todos os namespaces
```

**Pontos de atenção:**

- Nem tudo é "namespaced": nós, PersistentVolumes e os próprios namespaces são recursos **de cluster** (`kubectl api-resources` mostra a coluna `NAMESPACED`).
- Deletar um namespace **deleta tudo dentro dele**. Poderoso para limpar ambientes de teste; catastrófico no contexto errado (lembre-se do hábito de conferir o contexto, Capítulo 2).
- Namespaces **não isolam rede por padrão**: um Pod em `dev` alcança um Pod em `prod` normalmente, e o DNS interno até facilita (`servico.namespace.svc.cluster.local` — Capítulo 4). Isolamento real exige NetworkPolicies (Capítulo 8).
- Convenção comum de mercado: um namespace por equipe/aplicação por ambiente (ex.: `pagamentos-dev`, `pagamentos-prod`), com quotas e RBAC por namespace.

### 3.3.2 Labels, selectors e annotations

**Labels** são pares chave/valor anexados a qualquer objeto. São **o mecanismo de vínculo do Kubernetes**: nada "aponta" para Pods por nome — tudo os **seleciona por labels**. Você já viu isso o capítulo inteiro:

- O ReplicaSet encontra seus Pods pelo `selector`;
- O Deployment idem;
- O Service (Capítulo 4) escolhe para quem mandar tráfego por labels;
- O scheduler pode usar labels de nós para decidir onde agendar (Capítulo 7).

```yaml
metadata:
  labels:
    app: api-pedidos            # qual aplicação
    tier: backend               # camada
    environment: prod           # ambiente
    version: "2.4.1"            # versão
```

> Existe um conjunto de **labels recomendadas** pela comunidade (`app.kubernetes.io/name`, `app.kubernetes.io/version`, `app.kubernetes.io/part-of`...) — adotá-las melhora a integração com ferramentas do ecossistema (Helm, dashboards).

**Selectors em ação no kubectl:**

```bash
kubectl get pods -l app=api-pedidos                  # igualdade
kubectl get pods -l environment=prod,tier=backend    # E lógico
kubectl get pods -l 'environment in (dev,homolog)'   # conjuntos
kubectl get pods -l app --show-labels                # "tem a chave app"
kubectl delete pods -l app=teste                     # operações em massa por label
```

E nos objetos, o campo `selector` — com `matchLabels` (igualdade) ou `matchExpressions` (operadores `In`, `NotIn`, `Exists`):

```yaml
selector:
  matchLabels:
    app: web
  matchExpressions:
  - { key: environment, operator: In, values: [prod, homolog] }
```

**Cuidado clássico**: labels são a "cola" entre objetos, e cola errada gruda coisa errada. Se dois Deployments diferentes usarem o mesmo par `app: web` no template, os ReplicaSets de um podem "adotar" ou contar Pods do outro, e um Service pode mandar tráfego para a aplicação errada. Capriche na unicidade das combinações.

**Annotations** também são pares chave/valor, mas com papel diferente: **metadados não usados para seleção**. Servem para informação e para configurar ferramentas:

```yaml
metadata:
  annotations:
    kubernetes.io/change-cause: "upgrade nginx 1.28"          # histórico de rollout
    prometheus.io/scrape: "true"                              # instruções para o Prometheus
    nginx.ingress.kubernetes.io/rewrite-target: /             # configuração de Ingress (Cap. 4)
    equipe: "plataforma — contato: #plataforma no Slack"      # documentação livre
```

**Regra de bolso**: se serve para **agrupar/selecionar** objetos → label; se é **informação ou configuração** lida por humanos e ferramentas → annotation. (Labels têm restrições de tamanho/formato justamente porque são indexadas para busca; annotations aceitam valores longos e arbitrários.)

**Exercício de fixação 3.3**
1. Sua empresa tem os times "pagamentos" e "catálogo", cada um com ambientes dev e prod, tudo em um cluster. Proponha uma estrutura de namespaces e duas políticas que você aplicaria por namespace.
2. Por que deletar um Pod pelo nome é raro na prática, enquanto operar por labels é comum? Dê um exemplo de comando.
3. `version: "2.4.1"` deveria ser label ou annotation? E a URL do runbook de incidentes? Justifique.
4. Dois Deployments no mesmo namespace usam `app: web` no template dos Pods. Descreva um problema concreto que isso pode causar.

---

## Laboratório consolidado do capítulo

Do zero ao rollback, exercitando todos os objetos (~30 min):

```bash
minikube start
kubectl create namespace lab3
kubectl config set-context --current --namespace=lab3

# 1. Pod avulso com probes — observe, depois delete (ninguém o recria!)
kubectl run solo --image=nginx:1.27
kubectl get pod solo -w                      # Running; Ctrl+C
kubectl delete pod solo && kubectl get pods  # sumiu para sempre

# 2. Deployment com readiness — o self-healing de verdade
kubectl create deploy web --image=nginx:1.27 --replicas=3 --dry-run=client -o yaml > web.yaml
# (edite web.yaml e adicione a readinessProbe httpGet / porta 80 no container)
kubectl apply -f web.yaml
kubectl get rs,pods --show-labels
kubectl delete pod -l app=web --wait=false && kubectl get pods -w   # renascem; Ctrl+C

# 3. Rolling update e rollback
kubectl set image deploy/web nginx=nginx:1.28 && kubectl rollout status deploy/web
kubectl get rs                               # dois RS: o antigo zerado é o histórico
kubectl set image deploy/web nginx=nginx:1.99-inexistente
kubectl get pods                             # ImagePullBackOff só nos novos
kubectl rollout undo deploy/web && kubectl rollout status deploy/web

# 4. Job e CronJob
kubectl create job soma --image=busybox:1.36 -- sh -c 'echo $((2+2)) && sleep 2'
kubectl get jobs,pods && kubectl logs job/soma
kubectl create cronjob tique --image=busybox:1.36 --schedule="*/1 * * * *" -- date
sleep 70 && kubectl get jobs                 # um Job criado pelo CronJob

# 5. Seleção por labels
kubectl get all -l app=web
kubectl label pods -l app=web inspecionado=sim
kubectl get pods -L inspecionado

# 6. Limpeza total em um comando (o poder — e o perigo — do namespace)
kubectl delete namespace lab3
kubectl config set-context --current --namespace=default
```

---

## Resumo do capítulo

- O **Pod** é a unidade mínima: um ou mais containers com IP, portas e volumes compartilhados, sempre no mesmo nó. Pods são **efêmeros** — nunca conserte, substitua.
- **Multi-container** só para acoplamento forte (sidecar, ambassador, adapter); **init containers** preparam o terreno; desde o 1.29 há sidecars nativos.
- **Probes**: liveness reinicia (teste só o que restart resolve), readiness tira do balanceamento (dependências entram aqui), startup protege inicializações lentas.
- **ReplicaSet** mantém N réplicas via selector + template; o **Deployment** o gerencia para entregar rolling updates com histórico e **rollback** (`rollout undo`). É o padrão para stateless.
- **DaemonSet** = um por nó; **StatefulSet** = identidade e volume por réplica; **Job/CronJob** = tarefas finitas e agendadas.
- **Namespaces** organizam e delimitam políticas (mas não isolam rede por padrão); **labels/selectors** são a cola que liga tudo; **annotations** carregam metadados e configuração de ferramentas.

**Ponte para o Capítulo 4**: seus Pods estão rodando, com réplicas e self-healing — mas cada um tem um IP efêmero que muda a cada recriação. Como alguém os encontra de forma estável? Como o mundo externo chega até eles? Entram em cena os Services, o DNS interno e o Ingress.
