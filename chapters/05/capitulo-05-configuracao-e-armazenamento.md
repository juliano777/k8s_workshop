# Capítulo 5 — Configuração e armazenamento

> **Objetivos de aprendizagem**
> Ao final deste capítulo, você será capaz de:
> 1. Externalizar configurações com ConfigMaps e consumi-las em Pods.
> 2. Usar Secrets corretamente, conhecendo suas limitações reais de segurança.
> 3. Decidir entre variáveis de ambiente e volumes montados para cada tipo de configuração.
> 4. Diferenciar volumes efêmeros de persistentes e explicar o par PersistentVolume/PersistentVolumeClaim.
> 5. Explicar StorageClasses e o provisionamento dinâmico de armazenamento.
> 6. Implantar um PostgreSQL com StatefulSet, entendendo headless services e identidade estável.

---

## 5.1 Configuração de aplicações

Relembre a regra do Capítulo 1: **imagens são imutáveis e portáteis**. A mesma imagem `loja/api:2.4.1` deve rodar em dev, homolog e prod. O que muda entre os ambientes — URLs de banco, feature flags, níveis de log, credenciais — **não pode viver dentro da imagem**. Configuração é externa e injetada na hora de rodar. O Kubernetes oferece dois objetos para isso.

### 5.1.1 ConfigMaps

Um **ConfigMap** é um dicionário de pares chave/valor para configuração **não sensível**. As chaves podem guardar valores curtos ou arquivos inteiros:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-config
data:
  # valores simples
  LOG_LEVEL: "info"
  FEATURE_CHECKOUT_V2: "true"
  # um arquivo inteiro como valor (repare no | do YAML)
  app.properties: |
    cache.ttl=300
    pagination.size=20
```

Formas de criar:

```bash
kubectl create configmap api-config \
  --from-literal=LOG_LEVEL=info \
  --from-file=app.properties            # cada arquivo vira uma chave
# (e claro, o modo do curso: YAML versionado + kubectl apply -f)
```

Um ConfigMap não faz nada sozinho — ele existe para ser **consumido por Pods**, de duas maneiras que a seção 5.1.3 compara em detalhe.

### 5.1.2 Secrets (e suas limitações de segurança)

**Secrets** têm a mesma mecânica dos ConfigMaps, mas para dados **sensíveis**: senhas, tokens, chaves de API, certificados (você já criou um, o `kubernetes.io/tls` do Capítulo 4).

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque                      # o tipo genérico
data:                             # valores em base64
  DB_USER: bG9qYQ==
  DB_PASSWORD: czNjcjN0bzEyMw==
stringData:                       # alternativa: texto puro (o K8s codifica ao salvar)
  DB_HOST: "db"
```

```bash
kubectl create secret generic db-credentials \
  --from-literal=DB_USER=loja \
  --from-literal=DB_PASSWORD='s3cr3to123'
```

**Agora, a parte mais importante desta seção — o que um Secret NÃO é:**

> **Base64 não é criptografia.** É apenas codificação, reversível por qualquer um:
> ```bash
> kubectl get secret db-credentials -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
> # s3cr3to123
> ```

As limitações reais, e o que fazer sobre cada uma:

| Limitação | Mitigação |
|---|---|
| Por padrão, Secrets ficam em **texto claro no etcd** | Habilitar *encryption at rest* no API server (config do Capítulo 6) |
| Quem pode `get secrets` lê tudo | **RBAC** restritivo sobre o verbo/recurso (Capítulo 8) |
| Secrets em YAML no Git = senhas vazadas no histórico | **Nunca** commitar Secrets. Usar **Sealed Secrets** (criptografa para o Git) ou **External Secrets Operator** (busca de um cofre: Vault, AWS Secrets Manager...) — visão geral no Capítulo 8 |
| Visíveis para quem tem acesso ao nó/container | Montagens `tmpfs` (padrão), princípio do menor privilégio |

Então por que usar Secrets, se são "fracos"? Porque são a **interface padrão**: probes de segurança à parte, todo o ecossistema (Ingress TLS, imagePullSecrets, ServiceAccounts, operators de banco) integra com Secrets. As soluções maduras (Vault, Sealed Secrets) não os substituem — **alimentam** Secrets de forma segura. Você usa o objeto; muda a origem dele.

> Um subtipo que você usará ao trabalhar com registries privados: `kubectl create secret docker-registry` + campo `imagePullSecrets` no Pod — é assim que o kubelet se autentica para baixar imagens privadas.

### 5.1.3 Variáveis de ambiente vs. volumes montados

Tanto ConfigMaps quanto Secrets podem chegar ao container por dois caminhos:

**Caminho 1 — Variáveis de ambiente:**

```yaml
spec:
  containers:
  - name: api
    image: loja/api:2.4.1
    env:
    - name: LOG_LEVEL                       # uma chave específica
      valueFrom:
        configMapKeyRef:
          name: api-config
          key: LOG_LEVEL
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: DB_PASSWORD
    envFrom:                                # OU: todas as chaves de uma vez
    - configMapRef:
        name: api-config
```

**Caminho 2 — Volume montado (cada chave vira um arquivo):**

```yaml
spec:
  containers:
  - name: api
    image: loja/api:2.4.1
    volumeMounts:
    - name: config
      mountPath: /etc/app                   # ls /etc/app → LOG_LEVEL, app.properties...
      readOnly: true
  volumes:
  - name: config
    configMap:
      name: api-config
```

**A comparação que orienta a escolha:**

| | Variáveis de ambiente | Volume montado |
|---|---|---|
| Formato natural | Valores curtos (12-factor) | Arquivos de configuração inteiros |
| Atualização do ConfigMap/Secret | **Não** propaga — exige recriar o Pod | **Propaga sozinha** (após ~1 min), sem restart |
| Exposição acidental | Aparecem em `kubectl describe pod`? Não, mas vazam fácil: logs de crash, `/proc/<pid>/environ`, dumps de diagnóstico | Arquivos com permissão controlada, em tmpfs (Secrets) |
| Consumo pela aplicação | `os.getenv()` — universal | App precisa ler/observar arquivos |

**Regras de bolso do curso:**

1. Configuração simples e estável → **env** (é o que a maioria dos frameworks espera).
2. Arquivos de configuração (nginx.conf, application.yaml) → **volume**, sempre.
3. **Secrets → prefira volume**: menor superfície de vazamento acidental.
4. Precisa de atualização sem redeploy → **volume** (e a aplicação precisa reler o arquivo; nem toda app faz isso sozinha).

> **Pegadinha de prova (e de produção)**: mudar um ConfigMap **não** reinicia os Pods que o usam via env. O padrão comum é tratar configuração como parte do deploy: mudou config → novo rollout (ferramentas como Helm fazem isso anotando um hash da config no template do Pod — Capítulo 11).

**Exercício de fixação 5.1**
1. Por que "colocar a URL do banco no Dockerfile" viola o princípio da imagem imutável? O que quebra entre ambientes?
2. Demonstre (comando) por que base64 não protege um Secret. Cite duas medidas reais de proteção.
3. Para cada item, env ou volume — e por quê: (a) `PAGINATION_SIZE=20`; (b) um `nginx.conf` completo; (c) a senha do banco; (d) uma feature flag que precisa mudar sem redeploy.
4. Você atualizou um ConfigMap consumido via `envFrom` e nada mudou na aplicação. Explique o comportamento e duas formas de propagar a mudança.

---

## 5.2 Armazenamento persistente

### 5.2.1 Volumes efêmeros vs. persistentes

Desde o Capítulo 1 você sabe: a camada de escrita do container **morre com ele**. Volumes existem para dados que precisam durar mais — mas "durar mais" tem gradações:

**Volumes efêmeros — vivem enquanto o Pod vive:**

- **`emptyDir`**: um diretório vazio criado quando o Pod é agendado, compartilhável entre os containers do Pod (foi o que usamos no sidecar de logs do Capítulo 3). Sobrevive a *restarts do container*, mas é destruído com o Pod. Ótimo para cache, scratch e comunicação entre containers. (Variante `medium: Memory` = tmpfs.)
- **`configMap` / `secret`**: sim, as montagens da seção anterior são volumes efêmeros.
- **`hostPath`**: monta um diretório **do nó** dentro do Pod. Cuidado triplo: os dados ficam presos àquele nó (o Pod pode renascer em outro!), é um risco de segurança (acesso ao filesystem do host) e não tem lugar em aplicações comuns — uso legítimo é para agentes de nó (DaemonSets, Capítulo 3).

**A escada da persistência:**

```
camada de escrita   →  morre com o CONTAINER
emptyDir            →  morre com o POD
hostPath            →  sobrevive ao Pod, mas preso ao NÓ
PersistentVolume    →  independe de container, Pod e (idealmente) nó
```

Para dados de verdade — o banco, os uploads dos usuários — precisamos do último degrau: armazenamento com ciclo de vida **próprio**, desacoplado dos Pods. É o assunto do resto da seção.

### 5.2.2 PersistentVolume e PersistentVolumeClaim

O Kubernetes separa o armazenamento em dois objetos, espelhando dois papéis humanos:

- **PersistentVolume (PV)** — *o lado da infraestrutura*: "existe um disco de 10 Gi, deste tipo, com estas capacidades". Recurso **de cluster** (não namespaced), criado pelo administrador ou automaticamente (5.2.3).
- **PersistentVolumeClaim (PVC)** — *o lado da aplicação*: "preciso de 5 Gi, com tal modo de acesso". Recurso **do namespace**, criado pelo desenvolvedor, **sem saber nem se importar** de onde o disco vem.

O Kubernetes faz o **binding**: encontra (ou cria) um PV que satisfaça o pedido e os liga um ao outro, exclusivamente. O Pod, por sua vez, referencia **apenas o PVC**:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dados-api
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: api
spec:
  containers:
  - name: app
    image: loja/api:2.4.1
    volumeMounts:
    - name: dados
      mountPath: /var/lib/app
  volumes:
  - name: dados
    persistentVolumeClaim:
      claimName: dados-api          # o Pod só conhece o PVC
```

Essa indireção é o que torna os manifestos **portáteis**: o mesmo PVC funciona no Minikube (disco local), no cluster kubeadm on-prem (NFS, Ceph) e na AWS (EBS) — muda só o que está por trás.

**Access modes** (capacidade do storage, não permissão de arquivo):

- **RWO — ReadWriteOnce**: leitura/escrita por **um nó** por vez. O caso de discos de bloco (EBS, Ceph RBD) — e o que bancos de dados usam.
- **ROX — ReadOnlyMany**: leitura por muitos nós.
- **RWX — ReadWriteMany**: leitura/escrita por muitos nós simultaneamente — exige storage de arquivo (NFS, CephFS, EFS). Necessário quando várias réplicas escrevem no mesmo diretório (uploads compartilhados, por exemplo).

**Reclaim policy** — o destino do PV quando o PVC é deletado:

- `Delete`: o disco real é apagado junto (padrão no provisionamento dinâmico das nuvens).
- `Retain`: o PV fica `Released`, dados preservados, exigindo ação manual — a escolha prudente para dados críticos.

**Estados que você verá**: PVC `Pending` (nenhum PV compatível/aguardando provisionamento — os Events do describe dizem qual), `Bound` (ligado), PV `Released` (PVC deletado, dados retidos).

### 5.2.3 StorageClasses e provisionamento dinâmico

Criar PVs à mão para cada pedido não escala. A **StorageClass** automatiza: ela descreve um "perfil de storage" e aponta para um **provisioner** (um driver **CSI** — Container Storage Interface, o terceiro irmão dos padrões CRI e CNI) capaz de **criar o disco sob demanda**:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rapida
provisioner: ebs.csi.aws.com          # exemplos: pd.csi.storage.gke.io, rbd.csi.ceph.com...
parameters:
  type: gp3                           # parâmetros específicos do provisioner
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

O fluxo dinâmico completo:

```
PVC (storageClassName: rapida) ──▶ StorageClass ──▶ driver CSI cria o disco
        ──▶ PV criado automaticamente ──▶ binding ──▶ Pod monta e usa
```

Detalhes que valem pontos (na certificação e na vida):

- Um PVC **sem** `storageClassName` usa a classe **default** do cluster (a marcada com a annotation `is-default-class`). O Minikube tem uma (`standard`, do provisioner hostpath) — por isso PVCs "simplesmente funcionam" nele:
  ```bash
  kubectl get storageclass
  ```
- **`volumeBindingMode: WaitForFirstConsumer`**: adia a criação do disco até um Pod usar o PVC — assim o disco nasce **na zona/nó certo** onde o Pod foi agendado. (O alternativo, `Immediate`, pode criar o disco na zona A e o scheduler colocar o Pod na zona B: Pod preso em Pending.)
- **`allowVolumeExpansion: true`** permite crescer o volume editando o PVC (nunca encolher).
- Em clusters **kubeadm bare metal não existe provisioner por padrão** — instalaremos um no Capítulo 6 (ex.: local-path-provisioner ou NFS CSI), fechando mais uma peça que Minikube/k3s "davam de graça".

**Exercício de fixação 5.2**
1. Posicione na "escada da persistência": cache de sessão descartável; logs coletados por sidecar; dados do PostgreSQL; binários de um agente DaemonSet que lê o filesystem do nó.
2. Explique a divisão de papéis PV/PVC. Por que ela torna manifestos portáteis entre Minikube e AWS?
3. Três réplicas de um app precisam escrever no mesmo diretório de uploads. Que access mode isso exige e por que um disco EBS não serve?
4. O que `WaitForFirstConsumer` evita? Descreva o cenário de falha com `Immediate` em um cluster multi-zona.

---

## 5.3 StatefulSets na prática

### 5.3.1 Rodando um banco de dados (ex.: PostgreSQL) no cluster

Hora de juntar tudo: o StatefulSet (Capítulo 3), Secrets (5.1), PVCs e StorageClasses (5.2) — e rodar um banco de verdade.

**Por que Deployment não serve para banco?** Réplicas de Deployment são clones **intercambiáveis** atrás de um Service que balanceia. Um banco é o oposto: cada instância tem **seus** dados, papéis distintos (primário escreve, réplicas leem) e não pode ser "balanceado" cegamente. O StatefulSet fornece as garantias que faltam: **nome estável, disco próprio por réplica e ordem**.

**O manifesto completo (nosso maior YAML até aqui — leia os comentários):**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: pg-secret
stringData:
  POSTGRES_PASSWORD: "troque-me-depois"
---
apiVersion: v1
kind: Service                        # o headless service (detalhado em 5.3.2)
metadata:
  name: pg
spec:
  clusterIP: None                    # ← "headless": sem IP virtual
  selector:
    app: pg
  ports:
  - port: 5432
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: pg
spec:
  serviceName: pg                    # ← liga o STS ao headless service (obrigatório)
  replicas: 1                        # começamos simples; leia o aviso adiante
  selector:
    matchLabels:
      app: pg
  template:
    metadata:
      labels:
        app: pg
    spec:
      containers:
      - name: postgres
        image: postgres:16
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef: { name: pg-secret, key: POSTGRES_PASSWORD }
        - name: PGDATA                          # subdiretório evita conflito com lost+found
          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: dados
          mountPath: /var/lib/postgresql/data
        readinessProbe:
          exec:
            command: ["pg_isready", "-U", "postgres"]
          periodSeconds: 5
        resources:
          requests: { cpu: 250m, memory: 256Mi }
          limits: { memory: 512Mi }
  volumeClaimTemplates:              # ← A grande novidade do StatefulSet:
  - metadata:                        #    um MOLDE de PVC — cada réplica ganha o SEU,
      name: dados                    #    criado automaticamente: dados-pg-0, dados-pg-1...
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 2Gi
```

**O teste que prova a persistência:**

```bash
kubectl apply -f pg.yaml
kubectl get pods -w                          # pg-0 (nome ordinal!); Ctrl+C quando Ready
kubectl get pvc                              # dados-pg-0, criado pelo template

# grave dados
kubectl exec -it pg-0 -- psql -U postgres -c \
  "CREATE TABLE clientes(id serial, nome text); INSERT INTO clientes(nome) VALUES ('Ana'),('Bruno');"

# DESTRUA o Pod
kubectl delete pod pg-0
kubectl get pods -w                          # pg-0 renasce (mesmo nome!) e religa no MESMO PVC

# os dados sobreviveram?
kubectl exec -it pg-0 -- psql -U postgres -c "SELECT * FROM clientes;"
#  id | nome
# ----+-------
#   1 | Ana
#   2 | Bruno
```

Isso é o contrato do StatefulSet em ação: **o Pod morreu, a identidade e o disco não**.

> **Aviso de maturidade (importante para o seu curso ser honesto):** subir **réplicas** de PostgreSQL não é `replicas: 3` — replicação, failover e backup de banco são problemas de *operação*, não de agendamento. `replicas: 3` daria três bancos independentes e vazios, não um cluster. É exatamente para codificar esse conhecimento operacional que existem **Operators** como o **CloudNativePG** (Capítulo 10) — ou, alternativamente, usa-se banco gerenciado fora do cluster (RDS etc.), decisão legítima e comum. A regra prática: *rodar banco no Kubernetes, hoje, é viável e maduro — desde que via Operator; na mão, só para estudo.*

### 5.3.2 Headless services e identidade estável

Falta explicar a peça `clusterIP: None`. Um Service normal dá **um** IP virtual e **balanceia** — ótimo para clones, péssimo para réplicas com papéis. O **headless service** inverte a lógica:

- **Sem IP virtual, sem balanceamento.** O DNS do Service devolve **os IPs dos Pods** diretamente.
- Combinado com o StatefulSet (`serviceName`), cria o que realmente importa: **um registro DNS estável e individual por réplica**:

```
pg-0.pg.default.svc.cluster.local   →  IP atual do pg-0
pg-1.pg.default.svc.cluster.local   →  IP atual do pg-1
pg-2.pg.default.svc.cluster.local   →  IP atual do pg-2
```

O IP do Pod continua efêmero — mas **o nome não**. `pg-0` renasce com outro IP e o DNS o acompanha. É essa a "identidade estável" prometida no Capítulo 3, agora completa: **nome ordinal + DNS individual + PVC próprio**.

**Para que isso serve na prática:**

- Configurar replicação: a réplica aponta para `pg-0.pg` (o primário) pelo nome, para sempre.
- Sistemas distribuídos (Kafka, etcd, Elasticsearch) que precisam listar seus pares na configuração: a lista é previsível antes mesmo dos Pods existirem.
- Clientes que precisam falar com um membro específico, não com "qualquer um".

**Padrão comum em produção** — dois Services para o mesmo StatefulSet:

```
pg   (headless)  → identidade: pg-0.pg, pg-1.pg...     (replicação, peers)
pg-rw (normal)   → ClusterIP com selector no primário   (aplicações escrevem aqui)
pg-ro (normal)   → ClusterIP nas réplicas                (aplicações leem aqui)
```

(Manter o selector do `pg-rw` apontando para o primário correto durante um failover é, de novo, trabalho de Operator — o CloudNativePG cria exatamente esses três Services por você. O Capítulo 10 fecha esse ciclo.)

**Verifique o DNS individual:**

```bash
kubectl run cliente --rm -it --image=busybox:1.36 -- sh
nslookup pg                    # devolve o(s) IP(s) dos PODS, não um VIP
nslookup pg-0.pg               # o registro individual do pg-0
exit
```

**Exercício de fixação 5.3**
1. Por que `replicas: 3` em um Deployment de PostgreSQL está errado duas vezes (uma do Capítulo 3, outra deste)?
2. O que o `volumeClaimTemplates` faz que um `volumes.persistentVolumeClaim` comum não faz? O que acontece com os PVCs quando você deleta o StatefulSet?  *(Dica: teste — eles são preservados por padrão, e isso é proposital.)*
3. Explique a diferença entre `nslookup pg` com Service normal e com headless. Que caso de uso exige o segundo?
4. Uma réplica de leitura precisa se conectar permanentemente ao primário. Por que `pg-0.pg` é a resposta certa, e não o IP do pg-0 nem um Service ClusterIP comum?

---

## Laboratório consolidado do capítulo

Uma "aplicação com banco" de ponta a ponta (~40 min):

```bash
minikube start
kubectl create namespace lab5
kubectl config set-context --current --namespace=lab5

# 1. A prova do efêmero (relembrando o motivo de tudo)
kubectl run efemero --image=postgres:16 --env=POSTGRES_PASSWORD=x
kubectl exec efemero -- sh -c 'echo dados > /tmp/importante'
kubectl delete pod efemero
# recrie e confira: /tmp/importante não existe. Containers esquecem.

# 2. Configuração externalizada
kubectl create configmap api-config --from-literal=LOG_LEVEL=debug
kubectl create secret generic pg-secret --from-literal=POSTGRES_PASSWORD='s3nh4-lab'
kubectl get secret pg-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d; echo
# ↑ a prova de que base64 não é criptografia

# 3. Storage dinâmico do cluster
kubectl get storageclass                     # a classe default do Minikube

# 4. O banco: aplique o manifesto pg.yaml da seção 5.3.1 (Secret já criado no passo 2)
kubectl apply -f pg.yaml
kubectl get pods,pvc -w                      # pg-0 Ready + dados-pg-0 Bound; Ctrl+C

# 5. Grave, destrua, comprove
kubectl exec -it pg-0 -- psql -U postgres -c \
 "CREATE TABLE pedidos(id serial, item text); INSERT INTO pedidos(item) VALUES ('livro');"
kubectl delete pod pg-0 && kubectl get pods -w        # renasce como pg-0; Ctrl+C
kubectl exec -it pg-0 -- psql -U postgres -c "SELECT * FROM pedidos;"   # o livro está lá

# 6. Uma aplicação consumindo tudo (env de ConfigMap + Secret + DNS do banco)
kubectl run api --image=busybox:1.36 --restart=Never --env=DB_HOST=pg-0.pg -- \
  sh -c 'echo "conectaria em $DB_HOST"; sleep 3600' --overrides=''
kubectl exec api -- nslookup pg-0.pg         # identidade estável, na prática

# 7. O que sobrevive a quê (pergunta-síntese do capítulo)
kubectl delete statefulset pg
kubectl get pvc                              # dados-pg-0 CONTINUA aqui — por design
kubectl apply -f pg.yaml                     # o banco volta... com os dados antigos!
kubectl exec -it pg-0 -- psql -U postgres -c "SELECT * FROM pedidos;"

# 8. Limpeza
kubectl delete namespace lab5                # (isto sim, leva os PVCs junto)
kubectl config set-context --current --namespace=default
```

---

## Resumo do capítulo

- Configuração é **externa à imagem**: **ConfigMaps** para o que não é sensível, **Secrets** para o que é — sabendo que **base64 não é criptografia** e que a proteção real vem de encryption at rest, RBAC e ferramentas como Sealed Secrets/External Secrets (que alimentam Secrets, não os substituem).
- **Env vs. volume**: env para valores simples (mas não propaga mudanças); volume para arquivos, para Secrets (menos vazamento) e para atualização sem redeploy.
- A escada da persistência: camada de escrita < `emptyDir` < `hostPath` < **PV/PVC**. O PVC é o pedido portátil da aplicação; o PV, a entrega da infraestrutura; a **StorageClass** + driver **CSI** automatizam a criação (provisionamento dinâmico), com `WaitForFirstConsumer` garantindo o disco no lugar certo.
- O **StatefulSet** entrega identidade completa: nome ordinal (`pg-0`), **PVC próprio por réplica** (`volumeClaimTemplates`, preservados na deleção) e **DNS individual estável** via **headless service** (`clusterIP: None`).
- Banco no Kubernetes: viável e maduro **via Operator** (CloudNativePG — Capítulo 10); múltiplas réplicas "na mão" não formam um cluster de banco.

**Ponte para o Capítulo 6**: até aqui, o Minikube escondeu a infraestrutura: CNI pronto, StorageClass pronta, um nó só. Chegou a hora do curso cumprir sua promessa — construir, com kubeadm e as próprias mãos, um cluster real de 3+ nós, escolhendo e instalando cada uma dessas peças.
