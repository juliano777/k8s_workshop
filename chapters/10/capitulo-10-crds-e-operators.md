# Capítulo 10 — Estendendo o Kubernetes: CRDs e Operators

> **Objetivos de aprendizagem**
> Ao final deste capítulo, você será capaz de:
> 1. Explicar por que a API do Kubernetes é extensível e o que uma CRD adiciona ao cluster.
> 2. Criar uma CRD, instanciar Custom Resources e operá-los com o kubectl de sempre.
> 3. Escrever validação OpenAPI para CRDs e explicar o versionamento de APIs customizadas.
> 4. Definir o padrão Operator e reconhecer seus níveis de maturidade (capability levels).
> 5. Instalar, usar e remover com segurança Operators reais: cert-manager, Prometheus Operator e CloudNativePG.
> 6. Descrever a anatomia de um controller (watch/reconcile/status), as ferramentas para construí-lo e os critérios Operator vs. Helm vs. scripts.

> **O capítulo da recompensa.** Você vem cruzando com Operators desde o Capítulo 4 (cert-manager prometido), 6 (o operator do Calico que você instalou), 9 (Prometheus Operator dentro da stack) — e o Capítulo 5 terminou com uma dívida explícita: *"rodar banco no Kubernetes é maduro, desde que via Operator"*. Este capítulo paga todas essas promessas, e mostra que você já entende 80% do assunto sem saber: um Operator é apenas o loop de reconciliação do Capítulo 1 aplicado a conceitos que **você** define.

---

## 10.1 Extensibilidade da API

### 10.1.1 Custom Resource Definitions (CRDs)

Pare e observe o que o Kubernetes realmente é, com os olhos de quem completou nove capítulos: **um banco de estado desejado (etcd) atrás de uma API declarativa (apiserver), com loops que reconciliam** (controllers). Pod, Deployment, Service... são "apenas" tipos registrados nessa API, cada um com seu controller.

A pergunta que muda tudo: *e se essa máquina aceitasse tipos **seus**?* É exatamente o que uma **CustomResourceDefinition (CRD)** faz — registra um novo `kind` na API do cluster:

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  # nome OBRIGATORIAMENTE = <plural>.<group>
  name: cafeteiras.cozinha.exemplo.com
spec:
  group: cozinha.exemplo.com          # seu "apiGroup" (como apps, batch...)
  scope: Namespaced                   # ou Cluster (lembre a distinção do Cap. 3)
  names:
    kind: Cafeteira                   # o que vai no campo kind:
    plural: cafeteiras                # kubectl get cafeteiras
    singular: cafeteira
    shortNames: [cafe]                # kubectl get cafe  (como po, svc, deploy!)
  versions:
  - name: v1alpha1
    served: true                      # a API aceita chamadas desta versão
    storage: true                     # é a versão gravada no etcd
    schema:
      openAPIV3Schema:                # (validação — seção 10.1.3)
        type: object
        properties:
          spec:
            type: object
            properties:
              tipo:     { type: string }
              xicaras:  { type: integer }
```

Aplicada a CRD, o cluster **ganhou uma API nova**: endpoints REST, armazenamento no etcd, RBAC aplicável (Capítulo 8: `resources: ["cafeteiras"]` numa Role funciona!), tudo de graça. O que ele **não** ganhou — e essa distinção é o coração do capítulo — é **comportamento**: nada acontece quando uma Cafeteira é criada, porque nenhum controller a observa. CRD = substantivo novo; o verbo vem na seção 10.2.

> Você já usou dezenas de CRDs sem cerimônia: `Installation` do Calico (Capítulo 6), `ServiceMonitor`/`Prometheus` da stack (Capítulo 9), `ExternalSecret` (Capítulo 8), `SealedSecret`... Liste as do seu cluster e reconheça as histórias: `kubectl get crds`.

### 10.1.2 Criando e consultando um Custom Resource com kubectl

Com a CRD instalada, instâncias — os **Custom Resources (CRs)** — são YAML como outro qualquer, e **todo o ferramental dos Capítulos 2–3 simplesmente funciona**:

```yaml
apiVersion: cozinha.exemplo.com/v1alpha1
kind: Cafeteira
metadata:
  name: escritorio
spec:
  tipo: espresso
  xicaras: 8
```

```bash
kubectl apply -f cafeteira.yaml
kubectl get cafeteiras                     # ou: kubectl get cafe
kubectl describe cafeteira escritorio      # (Events apareceriam aqui — se houvesse controller)
kubectl get cafeteira escritorio -o yaml   # o objeto como está no etcd
kubectl explain cafeteira.spec             # ← até a documentação embutida funciona,
                                           #    gerada do schema OpenAPI!
kubectl edit cafeteira escritorio
kubectl delete cafeteira escritorio
```

Labels, annotations, `kubectl get -l`, RBAC, namespaces, `kubectl apply` idempotente, GitOps futuro — **tudo herda**. Essa é a genialidade do modelo: estender o Kubernetes não cria uma ferramenta paralela; cria cidadãos de primeira classe da mesma API. (Compare mentalmente com o mundo pré-Kubernetes: cada software com sua CLI, seu formato, seu daemon...)

Um refinamento que os bons projetos usam — **additionalPrinterColumns**, para o `kubectl get` mostrar o que importa:

```yaml
  versions:
  - name: v1alpha1
    additionalPrinterColumns:
    - name: Tipo
      type: string
      jsonPath: .spec.tipo
    - name: Xícaras
      type: integer
      jsonPath: .spec.xicaras
    - name: Pronta                     # virá do status (10.2.2)
      type: string
      jsonPath: .status.fase
```

```bash
kubectl get cafeteiras
# NAME         TIPO       XÍCARAS   PRONTA
# escritorio   espresso   8         ...
```

(É por isso que `kubectl get certificates` do cert-manager mostra READY e SECRET — colunas declaradas na CRD dele.)

### 10.1.3 Validação de schema (OpenAPI) e versionamento de CRDs

**Validação — o apiserver como guardião dos seus tipos.** O `openAPIV3Schema` não é decoração: o apiserver **rejeita na entrada** o que o viola (o portão de *admission* do Capítulo 8, trabalhando para a sua API). Um schema caprichado:

```yaml
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required: [tipo]                      # campo obrigatório
            properties:
              tipo:
                type: string
                enum: [espresso, coado, prensa]   # valores permitidos
              xicaras:
                type: integer
                minimum: 1
                maximum: 24                       # limites
              descricao:
                type: string
                maxLength: 200
```

```bash
# Prova:
kubectl apply -f - <<EOF
apiVersion: cozinha.exemplo.com/v1alpha1
kind: Cafeteira
metadata: { name: quebrada }
spec: { tipo: capuccino, xicaras: 99 }
EOF
# Error... spec.tipo: Unsupported value: "capuccino" ... spec.xicaras: Invalid value: 99
```

Erros na **borda**, com mensagens claras, antes de qualquer estado ruim entrar no etcd — a mesma qualidade de experiência dos tipos nativos. Recursos além do básico, para reconhecer em CRDs de mercado: `default:` (valores padrão), `x-kubernetes-validations` (regras **CEL**, ex.: "xicaras dobradas exigem tipo espresso"), e `pattern` (regex).

**Versionamento — a arte de evoluir sem quebrar.** Sua API vai mudar. O contrato de maturidade é o mesmo do Kubernetes que você já conhece (`v1` do core, `apps/v1`, `autoscaling/v2`...):

```
v1alpha1  →  experimental: pode mudar/sumir sem dó
v1beta1   →  estabilizando: mudanças com aviso
v1        →  estável: compatibilidade é compromisso
```

Mecânica de convivência entre versões — os três campos que importam:

- Várias versões podem estar **`served: true`** ao mesmo tempo (clientes antigos seguem funcionando).
- **Exatamente uma** é **`storage: true`** — a forma gravada no etcd; as demais são convertidas na leitura/escrita.
- Conversão entre versões: automática se for só renomear/reorganizar nada (estratégia `None`), ou via **conversion webhook** (um serviço seu traduz v1alpha1↔v1) quando a estrutura muda de verdade.

> Regra de ouro herdada da comunidade: **nunca remova nem mude o significado de um campo em versão servida** — adicione campos, deprecie com aviso, remova só em major novo. Quem já sofreu um upgrade de cluster com API removida (as release notes do 6.4.2!) sabe o valor dessa disciplina — agora ela é sua responsabilidade também.

**Exercício de fixação 10.1**
1. "CRD dá o substantivo; o controller dá o verbo." Explique com o experimento da Cafeteira: o que funcionou ao aplicá-la, e o que ficou faltando?
2. Liste três coisas que um CR herda de graça da máquina do Kubernetes e diga em que capítulo você as aprendeu.
3. Escreva o trecho de schema que impede `xicaras` negativas e torna `tipo` obrigatório com só dois valores. Onde e quando o erro aparece para o usuário?
4. Sua CRD está em v1alpha1 e você precisa renomear `spec.tipo` para `spec.metodo` já com usuários em produção. Desenhe a transição segura usando served/storage/conversão.

---

## 10.2 O padrão Operator

### 10.2.1 O que é um Operator: CRD + controller + conhecimento operacional

A definição em uma linha — e cada termo pesa:

> **Operator = CRD (a linguagem) + controller (o executor) + conhecimento operacional (a expertise humana, codificada).**

O terceiro termo é o diferencial. Pense no que o Capítulo 5 revelou sobre rodar PostgreSQL: réplicas não são clones; failover exige promover a réplica certa e redirecionar o Service; backup tem hora, método e teste de restore; upgrade de versão tem ordem. Esse conhecimento vivia em **runbooks e na cabeça do DBA** — executado manualmente, às 3h, sob pressão (o cenário que o Capítulo 9 te preparou para sobreviver).

O padrão Operator (cunhado pela CoreOS em 2016) propõe: **escreva esse runbook como software**. O DBA vira autor de um controller; o usuário escreve:

```yaml
kind: Cluster                    # CRD do CloudNativePG
spec:
  instances: 3
  backup: { ... }
```

...e o controller faz o que o especialista faria: provisiona com a topologia certa, monitora, promove no failover, agenda backups. **É o movimento que o curso inteiro ensaiou**: assim como o Deployment codificou "como fazer rolling update" (ninguém mais troca Pods na mão — Capítulo 3), um Operator codifica "como operar o software X". Operators são Deployments para conhecimento operacional arbitrário.

E a anatomia física é modesta — um Operator instalado é tipicamente: **CRDs + um Deployment** (o controller rodando como Pod comum) **+ RBAC** (a SA dele com as permissões de fazer o trabalho — Capítulo 8 aplicado). Nada de componentes mágicos: `kubectl get pods -n cert-manager` mostra o "operador" trabalhando.

### 10.2.2 O loop de reconciliação aplicado a recursos customizados

Nenhum conceito novo aqui — e isso é a beleza. O controller de um Operator roda **exatamente** o loop da seção 1.3.3, sobre os seus tipos:

```
        ┌──────────────────────────────────────────────┐
        │ OBSERVAR:  watch em Cafeteira (e nos objetos │
        │            que ele cria: Pods, Services...)  │
        └──────────────┬───────────────────────────────┘
                       ▼
        ┌──────────────────────────────────────────────┐
        │ COMPARAR:  spec (desejado) × mundo real      │
        │            (o que existe no cluster/externo) │
        └──────────────┬───────────────────────────────┘
                       ▼
        ┌──────────────────────────────────────────────┐
        │ AGIR:      criar/ajustar recursos nativos,   │
        │            chamar APIs, promover réplicas... │
        │ REPORTAR:  escrever em .status               │
        └──────────────┴────────▶ (de novo, para sempre)
```

Os detalhes que elevam o entendimento (e reaparecem quando você depurar Operators reais):

- **`spec` vs. `status` — o contrato sagrado**: o usuário escreve o spec; **só o controller** escreve o status (`fase: Pronta`, `replicasProntas: 3`, conditions). É como você sabe o que o Operator "pensa": `kubectl describe` no CR, seção Status + Events. Regra de depuração derivada: *CR com spec bonito e status vazio/estagnado = controller morto ou sem permissão* — e você já sabe investigar Pods e RBAC (Capítulos 8–9).
- **Ownership e garbage collection**: o controller marca o que cria com `ownerReferences` apontando para o CR — delete o CR, e o Kubernetes **cascateia** a deleção dos filhos (por isso deletar um `Cluster` do CNPG leva os Pods do banco junto; os PVCs, por escolha deliberada do operator, podem ficar — ecos do Capítulo 5).
- **Finalizers**: e quando deletar exige cerimônia (tirar um último backup, desregistrar de um sistema externo)? O controller adiciona um *finalizer* ao CR — a deleção fica "presa" (`Terminating`) até ele concluir a limpeza e remover o finalizer. (Agora você sabe diagnosticar o clássico "namespace preso em Terminating": algum finalizer não foi honrado — geralmente um controller já desinstalado. O Capítulo 9 agradece.)
- **Idempotência e nivelamento**: o reconcile pode rodar mil vezes pelas mesmas razões — deve sempre convergir ao mesmo resultado (o mesmo contrato do `kubectl apply`, Capítulo 2). Controllers reagem ao **estado**, não a "eventos perdíveis": se o controller reiniciar, a próxima reconciliação conserta o mundo.

### 10.2.3 Capability levels: de instalação básica a auto-pilot

Nem todo Operator entrega a mesma profundidade. A escala de maturidade do ecossistema (5 níveis) serve para **calibrar expectativas antes de adotar**:

| Nível | Nome | O que faz | Tradução prática |
|---|---|---|---|
| 1 | Basic Install | provisiona o software | "um Helm chart com passos a mais" |
| 2 | Seamless Upgrades | atualiza versões com segurança | upgrade vira editar o spec |
| 3 | Full Lifecycle | backup, restore, failover | **o runbook do DBA codificado** |
| 4 | Deep Insights | métricas, alertas, análise | integra com o Capítulo 9 sozinho |
| 5 | Auto Pilot | auto-scaling, auto-tuning, auto-healing fino | opera melhor que humanos de plantão |

Uso prático da tabela: um Operator nível 1–2 pode não justificar a dependência extra (Helm resolveria — seção 10.4.3); os níveis 3+ são onde o padrão brilha (CloudNativePG opera nos níveis altos: failover automático, backup contínuo, recovery point-in-time). Ao avaliar um Operator, procure no README/OperatorHub o nível declarado — e desconfie verificando: *o que exatamente acontece quando eu mato o Pod primário?*

**Exercício de fixação 10.2**
1. Complete a analogia e justifique: "o Deployment está para o rolling update assim como o CloudNativePG está para ______".
2. Um CR tem spec correto, mas status vazio há 20 minutos. Monte o roteiro de diagnóstico (3 passos) usando os Capítulos 8 e 9.
3. Explique como ownerReferences + finalizers produzem o sintoma "namespace preso em Terminating" e como resolvê-lo com segurança.
4. Por que "reagir ao estado" em vez de "reagir a eventos" torna um controller resiliente a reinícios? Conecte com a idempotência do `kubectl apply`.
5. Sua equipe avalia um Operator nível 2 para um software que o Helm já instala bem. Argumente contra a adoção — e diga que nível mudaria seu voto.

---

## 10.3 Usando Operators prontos (laboratório)

> A rota de valor imediato: **consumir** Operators maduros. O laboratório usa o cluster do Capítulo 6 (ou Minikube) e culmina pagando a dívida do Capítulo 5: um PostgreSQL de 3 instâncias com failover automático.

### 10.3.1 OperatorHub e formas de instalação

Onde encontrar: **OperatorHub.io** (o catálogo da comunidade, com os capability levels declarados), o **Artifact Hub** (charts e operators), e os repositórios oficiais de cada projeto. Como instalar — três vias, da mais comum à mais corporativa:

1. **Manifesto direto** (`kubectl apply -f <url>`): você já fez com o Calico e fará com o cert-manager. Simples e transparente — o YAML instala CRDs + Deployment + RBAC (confira você mesmo, agora que sabe a anatomia).
2. **Helm chart** (como a kube-prometheus-stack do Capítulo 9): parametrizável via values; atenção ao detalhe clássico de *CRDs em charts* (Helm as instala mas reluta em atualizá-las — leia as notas de upgrade de cada projeto).
3. **OLM (Operator Lifecycle Manager)**: um "operator de operators" que gerencia catálogo, dependências e upgrades — padrão no OpenShift, opcional fora dele. Para o curso, saber que existe basta.

### 10.3.2 Exemplos práticos: cert-manager, Prometheus Operator

**cert-manager — a promessa do Capítulo 4, paga.** O trabalho manual de lá (openssl → Secret → Ingress) vira declaração:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl get pods -n cert-manager          # controller, webhook, cainjector
kubectl get crds | grep cert-manager      # certificates, issuers, clusterissuers...
```

```yaml
# Uma autoridade emissora (para lab, self-signed; em produção, ACME/Let's Encrypt):
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: { name: lab-issuer }
spec: { selfSigned: {} }
---
# O pedido declarativo de certificado:
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: loja-cert }
spec:
  secretName: loja-tls                 # o Secret que ele vai criar/renovar
  dnsNames: [loja.exemplo.com]
  issuerRef: { name: lab-issuer, kind: ClusterIssuer }
```

```bash
kubectl get certificate loja-cert      # READY True (colunas da CRD!)
kubectl get secret loja-tls            # o kubernetes.io/tls do Capítulo 4 — criado por robô
kubectl describe certificate loja-cert # status + events: o controller narrando o trabalho
```

O loop em ação contínua: o controller observa o Certificate, emite, **renova antes de expirar, para sempre**. Com o issuer ACME de produção, a annotation `cert-manager.io/cluster-issuer` num Ingress automatiza até o pedido — TLS vira detalhe declarado.

**Prometheus Operator — revisitando o Capítulo 9 com olhos novos.** A stack que você instalou é operada por CRDs — e agora você as lê fluentemente:

```bash
kubectl get crds | grep monitoring.coreos.com
# prometheuses, servicemonitors, alertmanagers, prometheusrules...
```

O fluxo declarativo: sua aplicação expõe `/metrics` → você cria um **ServiceMonitor** (CR: "raspe os Services com estas labels") → o operator **regenera a configuração do Prometheus sozinho**. Monitorar um app novo = um YAML, zero edição de configuração central:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: api
  labels: { release: monitor }        # ← o selector que ESTA instalação da stack observa
spec:
  selector:
    matchLabels: { app: api }         # quais Services raspar
  endpoints:
  - port: metrics                     # nome da porta no Service
    interval: 30s
```

(O gotcha real embutido: ServiceMonitor ignorado quase sempre = label `release` não casando com o que o Prometheus seleciona — diagnostique com describe no CR `prometheus` e o método do Capítulo 9.)

### 10.3.3 Operators de banco de dados (ex.: CloudNativePG para PostgreSQL)

A dívida do Capítulo 5, quitada. Instale o **CloudNativePG** e declare o que lá era impossível:

```bash
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.25/releases/cnpg-1.25.0.yaml
kubectl get pods -n cnpg-system            # o controller
```

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-loja
spec:
  instances: 3                     # ← o "replicas: 3" que AGORA significa algo:
  storage:                         #    1 primário + 2 réplicas em streaming replication
    size: 2Gi
  # backup: { barmanObjectStore: ... }   # backup contínuo p/ S3 e PITR — produção
```

```bash
kubectl apply -f pg-cluster.yaml
kubectl get cluster pg-loja -w             # colunas da CRD: instâncias, primário, status
kubectl get pods -l cnpg.io/cluster=pg-loja -o wide
# pg-loja-1 (primário), pg-loja-2, pg-loja-3 — espalhados por anti-affinity (Cap. 7, de brinde!)
kubectl get svc
# pg-loja-rw / pg-loja-ro / pg-loja-r  ← os "dois Services" da seção 5.3.2, criados por robô
```

**O teste que vale o capítulo — o failover:**

```bash
kubectl delete pod pg-loja-1 &             # mate o PRIMÁRIO
kubectl get cluster pg-loja -w             # observe: "Failing over" → nova primária eleita
kubectl get pods -l cnpg.io/cluster=pg-loja
# Em segundos: uma réplica foi PROMOVIDA, o Service -rw já aponta para ela,
# e uma nova réplica é criada para repor a trinca. Nenhum humano acordou.
```

Compare com o Capítulo 5: lá, matar o `pg-0` provava a persistência do disco; aqui, matar o **primário** prova a persistência do **serviço**. A diferença entre as duas cenas é exatamente "conhecimento operacional codificado" — a definição de Operator, demonstrada. (Alternativas do mesmo nível para conhecer: CrunchyData PGO, Zalando postgres-operator; e o padrão se repete por todo o ecossistema: Strimzi para Kafka, ECK para Elasticsearch, MariaDB/MySQL operators...)

### 10.3.4 Ciclo de vida: instalação, upgrade e remoção segura

Operators são software rodando com **poderes elevados** no cluster — o ciclo de vida deles merece disciplina própria:

**Instalação consciente**: leia o RBAC que o manifesto pede (agora você sabe ler — Capítulo 8); fixe a **versão** do manifesto/chart (nunca "latest" de main — Capítulo 5/8); anote CRDs instaladas.

**Upgrade — a regra de ouro: CRDs primeiro, controller depois**, sempre pelas notas de release do projeto (upgrades de Operator podem migrar versões de API — o 10.1.3 na prática). E entenda a semântica: atualizar o *Operator* não atualiza necessariamente o *software gerido* (o CNPG novo não força PostgreSQL novo — isso é outro campo no spec do CR, mudado quando **você** decidir). Dois ciclos de vida distintos, de propósito.

**Remoção — a ordem importa e o perigo é real:**

```
1. Delete os CRs (e AGUARDE: finalizers fazendo limpeza — backups finais etc.)
2. Delete o Operator (controller, RBAC)
3. Por último, se realmente quiser: delete as CRDs
```

O motivo da cautela, em maiúsculas mentais: **deletar uma CRD deleta TODOS os CRs dela no cluster inteiro** — e, via ownerReferences, cascateia nos filhos. Deletar a CRD `clusters.postgresql.cnpg.io` num cluster com bancos vivos = deletar os bancos. Inversamente, remover o controller **antes** dos CRs deixa finalizers órfãos = objetos presos em Terminating (o diagnóstico do 10.2.2). A ordem 1→2→3 evita os dois desastres.

**Exercício de fixação 10.3**
1. Refaça mentalmente o fluxo TLS do Capítulo 4 e o do cert-manager. Liste o que deixou de ser tarefa humana — inclusive a que ninguém lembra de fazer (renovação).
2. Seu ServiceMonitor novo não aparece nos targets do Prometheus. Dois suspeitos e os comandos que os separam.
3. No failover do CNPG, enumere (na ordem) as ações que o controller executou — e aponte qual capítulo do curso ensinou cada mecanismo subjacente (Service selector, anti-affinity, PVC...).
4. Um colega propõe "limpar o cluster" com `kubectl delete crd --all`. Escreva o parágrafo que o impede, com os dois mecanismos de desastre envolvidos.
5. Upgrade do CNPG 1.25→1.26 disponível, e do PostgreSQL 16→17 também. São a mesma operação? Qual a ordem e onde cada uma é declarada?

---

## 10.4 Construindo seu próprio Operator (visão geral)

> Objetivo calibrado: não formar desenvolvedores de Operators em uma seção, mas dar o **mapa** — o suficiente para ler o código de um Operator, avaliar a decisão de construir e saber por onde começar se decidir.

### 10.4.1 Kubebuilder e Operator SDK

Ninguém escreve um controller "na unha" contra a API REST — o ecossistema Go oferece a pilha consolidada:

- **client-go** → cliente oficial da API (baixo nível);
- **controller-runtime** → a biblioteca que encapsula o padrão (watches, cache, filas, reconcile loop) — o coração de praticamente todo Operator moderno;
- **Kubebuilder** → o framework/scaffolding oficial (SIG API Machinery): `kubebuilder init` + `create api` geram projeto, tipos Go que **viram a CRD** (schema OpenAPI gerado dos structs + marcadores `+kubebuilder:validation:...` — o 10.1.3 de graça), RBAC, testes e manifests;
- **Operator SDK** (Red Hat) → construído **sobre** o Kubebuilder para Go (mesma experiência), adicionando integração com OLM e caminhos alternativos: **Ansible** e **Helm** operators — este último transforma um chart em operator nível 1–2 sem escrever Go (útil, com as limitações que a tabela de capability levels sugere).

Fora do mundo Go: **Kopf** (Python) e **Java Operator SDK** são maduros; a escolha padrão do mercado continua Go + Kubebuilder. Para o curso: **Kubebuilder é o caminho** se um dia você construir.

### 10.4.2 Anatomia de um controller: watch, reconcile, status

O código essencial de um Reconciler cabe numa tela — e cada linha ecoa a teoria do 10.2.2:

```go
// A função chamada a cada "algo mudou" relevante:
func (r *CafeteiraReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // 1. OBSERVAR — busque o CR (pode ter sumido: deleção é um caso normal!)
    var cafeteira cozinhav1.Cafeteira
    if err := r.Get(ctx, req.NamespacedName, &cafeteira); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)   // deletado? nada a fazer (GC cuida)
    }

    // 2. COMPARAR — o mundo está como o spec pede?
    var deploy appsv1.Deployment
    err := r.Get(ctx, tipos.NamespacedName{Name: cafeteira.Name, Namespace: cafeteira.Namespace}, &deploy)
    if apierrors.IsNotFound(err) {
        // 3. AGIR — crie o que falta, SEMPRE com ownerReference (GC! — 10.2.2)
        novo := r.deploymentParaCafeteira(&cafeteira)
        ctrl.SetControllerReference(&cafeteira, novo, r.Scheme)
        if err := r.Create(ctx, novo); err != nil {
            return ctrl.Result{}, err                      // erro → retry com backoff automático
        }
    }
    // ...convergências parciais: réplicas divergem? imagem mudou? ajuste, não recrie.

    // 4. REPORTAR — o contrato do status
    cafeteira.Status.Fase = "Pronta"
    if err := r.Status().Update(ctx, &cafeteira); err != nil {
        return ctrl.Result{}, err
    }
    return ctrl.Result{}, nil            // ou {RequeueAfter: 5*time.Minute} p/ revisitas periódicas
}

// O que dispara o Reconcile — os WATCHES:
func (r *CafeteiraReconciler) SetupWithManager(mgr ctrl.Manager) error {
    return ctrl.NewControllerManagedBy(mgr).
        For(&cozinhav1.Cafeteira{}).      // mudanças no MEU tipo
        Owns(&appsv1.Deployment{}).       // e nos FILHOS que eu criei (alguém mexeu? reconcilio!)
        Complete(r)
}
```

Os princípios embutidos, para levar (mesmo sem nunca escrever Go):

- **Um só caminho de código** para criar, atualizar e curar — o reconcile não distingue "primeira vez" de "consertando drift"; ele só converge. (Idempotência não é enfeite: é a estrutura.)
- **Erro → retorno → retry com backoff** gerenciado pela fila do controller-runtime — resiliência de graça.
- **`Owns()` fecha o círculo do self-healing**: delete o Deployment filho na mão e o watch dispara o reconcile, que o recria — seu CR ganhou a mesma teimosia que o ReplicaSet do Capítulo 3.
- E as responsabilidades de gente grande, citadas para constar: eventos (`record.Event` — os que aparecem no describe), conditions padronizadas no status, leader election quando houver réplicas do controller (o mesmo mecanismo do controller-manager — Capítulo 6), e testes com **envtest**.

### 10.4.3 Quando criar um Operator vs. usar Helm/scripts

A decisão de engenharia honesta — porque um Operator é **software que você passa a manter**:

| Ferramenta | Natureza | Brilha quando... |
|---|---|---|
| **Scripts/pipelines** | imperativos, rodam e terminam | tarefas pontuais, glue code, migrações one-shot |
| **Helm** (Capítulo 11) | template + install/upgrade; **age quando invocado** | instalar/configurar por ambiente, sem decisões contínuas em runtime |
| **Operator** | reconciliação **contínua**; decide sozinho | o dia 2 exige reações automáticas a eventos (failover, rotação, scaling fino) |

O teste decisivo em três perguntas:

1. **Existe decisão operacional contínua em runtime?** ("se o primário cair, promova"; "se o certificado expirar em 30 dias, renove") → só Operator faz isso. Se a resposta é "instala e pronto" → Helm.
2. **Já existe Operator maduro (nível 3+) para isso?** → **use-o**; construir seria reinventar com menos horas de produção.
3. **Você sustenta o custo?** Go, testes, versionamento de API (10.1.3!), segurança do RBAC elevado, upgrades — um Operator é um produto interno com roadmap.

E os erros de calibragem, nos dois sentidos: *over-engineering* — operator nível 1 para app stateless que um Deployment+Helm resolvem (a "doença do operator para tudo"); *under-engineering* — runbook manual de failover executado por humanos sonolentos quando um operator maduro existe na prateleira. A sabedoria do capítulo é reconhecer cada caso.

**Exercício de fixação 10.4**
1. No código do Reconciler: por que `IgnoreNotFound` no passo 1 não é preguiça, e qual mecanismo do 10.2.2 completa a história da deleção?
2. Explique como `Owns(&appsv1.Deployment{})` dá ao seu CR o comportamento do experimento "delete o Pod e ele volta" do Capítulo 3. Qual é o gatilho exato?
3. Classifique (script/Helm/Operator) e defenda: (a) instalar o Ingress-NGINX com valores por ambiente; (b) rotacionar credenciais de banco a cada 12h reagindo a um cofre; (c) popular o banco de homologação toda segunda-feira.
4. Sua empresa quer um operator para o produto interno "só para instalar mais fácil". Contra-argumente com a tabela de capability levels e proponha a alternativa.
5. (Síntese do capítulo) Escreva, em pseudo-código de 10 linhas, o reconcile de um operator de backup: CR `BackupAgendado{spec: {alvo, cron}}` → garante um CronJob (Capítulo 3) correspondente, com ownerReference e status.

---

## Laboratório consolidado do capítulo

Do substantivo ao auto-pilot (~60 min, cluster do Capítulo 6 ou Minikube):

```bash
kubectl create namespace lab10 && kubectl config set-context --current --namespace=lab10

# ── Parte A: sua primeira CRD (o substantivo sem verbo)
# 1. Aplique a CRD Cafeteira completa (com schema, enum, printer columns — seções 10.1.x)
# 2. Crie CRs válidos; use get/describe/explain/edit; comprove shortName e colunas
# 3. Tente o CR inválido (tipo: capuccino) e leia a rejeição do apiserver
# 4. kubectl get crds | wc -l  → conte quantas APIs seu cluster já ganhou no curso

# ── Parte B: cert-manager (nível: infraestrutura invisível)
# 5. Instale, crie o ClusterIssuer self-signed e o Certificate (10.3.2)
# 6. Prove o loop: delete o SECRET loja-tls e observe-o RENASCER (describe conta a história)
kubectl delete secret loja-tls && kubectl get secret loja-tls -w

# ── Parte C: CloudNativePG (nível: o DBA codificado)
# 7. Instale o operator; aplique o Cluster pg-loja com instances: 3 (10.3.3)
# 8. Mapeie a anatomia: kubectl get crds,deploy -n cnpg-system + RBAC da SA do controller
# 9. Grave dados (via svc pg-loja-rw, credenciais no Secret pg-loja-app — encontre-o!)
# 10. O TESTE: delete o pod primário e cronometre o failover assistindo
kubectl get cluster pg-loja -w
# 11. Confirme os dados intactos via pg-loja-rw (nova primária!) — Capítulos 5+10 fechados

# ── Parte D: remoção na ordem certa (e o desastre evitado)
# 12. Delete o CR Cluster → aguarde finalizers → observe o que ficou (PVCs? por quê?)
# 13. Só então remova o operator; discuta: e se tivéssemos deletado a CRD no passo 12?

kubectl delete namespace lab10
```

**Extensão para quem quer construir**: `kubebuilder init` + `create api` da Cafeteira; implemente o reconcile mínimo (Deployment de nginx com réplicas = xicaras/4); rode com `make run` local e faça o experimento do `Owns()` — delete o Deployment e veja seu controller recriá-lo.

---

## Resumo do capítulo

- O Kubernetes é uma **máquina genérica de estado desejado** — e **CRDs** registram tipos seus nela: API REST, etcd, RBAC, kubectl, `explain`, printer columns, tudo herdado. **Schema OpenAPI** valida na borda (enum, limites, required, CEL); **versionamento** (alpha→beta→v1, served/storage, conversion webhooks) é compromisso de compatibilidade.
- **Operator = CRD + controller + conhecimento operacional codificado** — o loop de reconciliação do Capítulo 1 sobre conceitos seus, com o contrato spec (usuário) / **status** (controller), **ownerReferences** (GC em cascata), **finalizers** (limpeza antes da morte — e a causa do "Terminating eterno") e idempotência por design. **Capability levels** 1–5 calibram expectativas: o padrão brilha do nível 3 (full lifecycle) em diante.
- Na prática: **cert-manager** (TLS declarativo que se renova sozinho — a promessa do Cap. 4), **Prometheus Operator** (monitoramento por CRs — o Cap. 9 por dentro) e **CloudNativePG** (o `instances: 3` que finalmente significa cluster de verdade, com failover automático — a dívida do Cap. 5, paga ao vivo). Ciclo de vida com disciplina: versão fixada, **CRDs antes do controller no upgrade**, e remoção na ordem CRs → operator → CRDs (deletar CRD = deletar todos os CRs e seus filhos!).
- Construção: **Kubebuilder/controller-runtime** (Go) geram CRD a partir de tipos; o Reconciler observa (`For`/`Owns`), converge com um só caminho de código idempotente e reporta no status. **Decisão honesta**: decisão contínua em runtime → Operator; instalação/configuração → Helm; tarefa pontual → script — e Operator maduro existente vence construir o seu.

**Ponte para o Capítulo 11**: dos Operators ficou um padrão — tudo que importa virou YAML declarativo. Mas quem aplica esses YAMLs? Como empacotar uma aplicação inteira com seus values por ambiente, e como garantir que o cluster reflita exatamente o que está no Git? Helm, Kustomize e GitOps fecham o ciclo — e o projeto final espera por você.
