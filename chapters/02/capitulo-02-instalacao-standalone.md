# Capítulo 2 — Instalação standalone (nó único)

> **Objetivos de aprendizagem**
> Ao final deste capítulo, você será capaz de:
> 1. Comparar Minikube, Kind, k3s e MicroK8s e escolher a ferramenta certa para cada cenário.
> 2. Instalar o kubectl e configurá-lo para conversar com um cluster.
> 3. Subir, verificar e destruir um cluster Kubernetes de nó único na sua máquina.
> 4. Navegar em contextos e entender o arquivo kubeconfig.
> 5. Usar os comandos essenciais do dia a dia: get, describe, logs e exec.
> 6. Explicar a diferença entre o modo imperativo e o declarativo, e aplicar seu primeiro manifesto YAML.

---

## 2.1 Opções para ambiente local

No Capítulo 1 vimos que um cluster tem control plane e nós de trabalho. Em um cluster **standalone (nó único)**, todos esses componentes rodam na mesma máquina — o nó é, ao mesmo tempo, control plane e worker. É o ambiente perfeito para aprender: você tem um Kubernetes completo e de verdade, sem precisar de vários servidores.

Existem quatro ferramentas consagradas para isso. Todas entregam um cluster funcional; o que muda é *como* elas o materializam.

### 2.1.1 Minikube

O Minikube é a ferramenta "oficial" de aprendizado do projeto Kubernetes e a mais antiga da lista.

- **Como funciona**: cria o cluster dentro de uma VM ou de um container, dependendo do *driver* escolhido (`docker`, `virtualbox`, `kvm2`, `hyperkit`, `qemu`...). Hoje o driver `docker` é o padrão na maioria das plataformas.
- **Pontos fortes**:
  - Sistema de **addons** com um comando (`minikube addons enable ingress`, `metrics-server`, `dashboard` etc.) — ótimo para o nosso curso, pois usaremos Ingress e metrics-server nos Capítulos 4 e 7.
  - Comandos de conveniência: `minikube service`, `minikube tunnel` (simula um LoadBalancer), `minikube dashboard`.
  - Suporta multi-nó (`--nodes 3`) e múltiplos perfis de cluster.
- **Pontos fracos**: mais pesado que o Kind; a camada de conveniência "esconde" um pouco a infraestrutura real.

### 2.1.2 Kind (Kubernetes in Docker)

O Kind roda **cada nó do cluster como um container Docker** — dentro de cada container, rodam o kubelet, o containerd e os Pods (containers dentro de containers).

- **Como funciona**: `kind create cluster` sobe um container que é o nó; um arquivo YAML de configuração permite criar clusters multi-nó em segundos.
- **Pontos fortes**:
  - **Extremamente rápido e leve** para criar e destruir clusters — por isso é o queridinho de pipelines de CI e de quem testa o próprio Kubernetes.
  - Multi-nó trivial: 3 nós = 3 containers. Será útil como "ensaio" antes do cluster real do Capítulo 6.
  - Reprodutível: a configuração do cluster vive em um arquivo versionável.
- **Pontos fracos**: sem sistema de addons (Ingress e LoadBalancer exigem passos manuais); acesso a serviços exige mapeamento de portas planejado na criação; exige Docker/Podman instalado.

### 2.1.3 k3s / MicroK8s

Diferente dos anteriores, estes dois não são "simuladores locais": são **distribuições completas de Kubernetes**, leves o suficiente para rodar direto no sistema operacional — inclusive em produção.

**k3s** (Rancher/SUSE, projeto CNCF)
- Um único binário de ~70 MB que instala um Kubernetes certificado em segundos: `curl -sfL https://get.k3s.io | sh -`.
- Substitui o etcd por SQLite por padrão (em nó único) e já embute containerd, CNI (Flannel), Ingress (Traefik) e um provedor de LoadBalancer.
- Roda até em Raspberry Pi; muito usado em **edge computing e IoT**, e também em produção de pequeno porte.
- Vira multi-nó facilmente — é uma das alternativas que exploraremos no Capítulo 6.

**MicroK8s** (Canonical)
- Instalado via snap (`sudo snap install microk8s --classic`); integração excelente com Ubuntu.
- Sistema de addons semelhante ao do Minikube (`microk8s enable dns ingress`).
- Também suporta clustering e alta disponibilidade.

A diferença essencial de mentalidade: Minikube/Kind criam clusters **descartáveis para desenvolvimento**; k3s/MicroK8s **instalam o Kubernetes na máquina** como um serviço permanente.

### 2.1.4 Comparativo: quando usar cada um

| Critério | Minikube | Kind | k3s | MicroK8s |
|---|---|---|---|---|
| Onde o cluster roda | VM ou container | Containers Docker | Direto no SO (systemd) | Direto no SO (snap) |
| Consumo de recursos | Médio | Baixo | Muito baixo | Baixo |
| Velocidade criar/destruir | Média | Muito alta | Alta (mas "instala") | Média |
| Addons prontos | Sim (rico) | Não | Embutidos (Traefik etc.) | Sim |
| Multi-nó | Sim | Sim (trivial) | Sim | Sim |
| Uso em produção | Não | Não | Sim (edge/pequeno porte) | Sim |
| SO suportado | Linux, macOS, Windows | Linux, macOS, Windows | Linux | Linux (VM em mac/win) |

**Recomendações práticas:**
- **Aprendizado geral e este curso** → **Minikube** (addons facilitam os próximos capítulos).
- **CI/CD e testes rápidos e descartáveis** → **Kind**.
- **Servidor Linux modesto, edge, Raspberry Pi, homelab** → **k3s**.
- **Ambiente Ubuntu, do laptop ao servidor** → **MicroK8s**.

> Neste capítulo, o laboratório principal usa **Minikube**, com um quadro alternativo para Kind. Nada impede você de reproduzir tudo nas quatro ferramentas — o Kubernetes lá dentro é o mesmo, e essa é justamente a lição.

**Exercício de fixação 2.1**
1. Qual a diferença fundamental entre o que o Kind faz e o que o k3s faz com a sua máquina?
2. Sua equipe precisa rodar testes de integração em cada pull request, criando e destruindo um cluster a cada execução. Qual ferramenta você escolheria e por quê?
3. Por que o k3s consegue ser tão menor que um Kubernetes "completo"? Cite duas simplificações que ele faz.

---

## 2.2 Instalação passo a passo (laboratório)

### 2.2.1 Pré-requisitos de máquina (CPU, RAM, virtualização)

**Mínimo para o Minikube com driver docker:**

- **2 vCPUs** (4 recomendado)
- **4 GB de RAM livres** (8 GB recomendado — o cluster padrão reserva 2 GB)
- **20 GB de disco livre**
- **Docker instalado e funcionando** (ou outro driver: VirtualBox, KVM, Hyper-V...)
- Conexão com a internet (para baixar imagens)

**Verificações antes de começar (Linux):**

```bash
# CPU e virtualização (saída > 0 indica suporte a VT-x/AMD-V; necessário só para drivers de VM)
grep -cE 'vmx|svm' /proc/cpuinfo

# Memória disponível
free -h

# Docker funcionando e seu usuário no grupo docker
docker version
docker run --rm hello-world
# Se falhar por permissão: sudo usermod -aG docker $USER && newgrp docker
```

> **Windows**: use WSL2 + Docker Desktop. **macOS**: Docker Desktop ou Colima. Em ambos, os comandos kubectl/minikube são idênticos aos do Linux — outra vantagem de containers e do padrão OCI.

### 2.2.2 Instalando o kubectl

O `kubectl` é o cliente de linha de comando que conversa com o kube-apiserver (lembre do Capítulo 1: *tudo* passa pelo API server). Ele é independente do cluster — o mesmo binário administra Minikube, k3s ou um cluster EKS na AWS.

**Linux (amd64):**

```bash
# Baixa a versão estável mais recente
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Instala no PATH
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verifica
kubectl version --client
```

**macOS:** `brew install kubectl` • **Windows:** `winget install Kubernetes.kubectl` (ou choco/scoop).

**Configurações de qualidade de vida (recomendado desde o primeiro dia):**

```bash
# Autocompletar (bash; existe equivalente para zsh/fish)
echo 'source <(kubectl completion bash)' >> ~/.bashrc

# Alias k — o padrão de fato da comunidade
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
source ~/.bashrc
```

> **Regra de compatibilidade**: o kubectl suporta clusters com ±1 versão minor de diferença (kubectl 1.33 funciona com clusters 1.32–1.34). Mantenha-o atualizado junto com o cluster.

### 2.2.3 Subindo o primeiro cluster de nó único

**Instale o Minikube:**

```bash
# Linux amd64
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64
```

(macOS: `brew install minikube` • Windows: `winget install Kubernetes.minikube`)

**Crie o cluster:**

```bash
minikube start --driver=docker
```

Acompanhe a saída — ela narra exatamente a teoria do Capítulo 1: baixa a imagem base do nó, cria o container/VM, inicializa o control plane (apiserver, etcd, scheduler, controller-manager), configura o kubelet e instala componentes básicos (CoreDNS, storage provisioner).

```
😄  minikube v1.36.x on Ubuntu 24.04
✨  Using the docker driver based on user configuration
🔥  Creating docker container (CPUs=2, Memory=4000MB) ...
🐳  Preparing Kubernetes v1.33.x on containerd ...
🔎  Verifying Kubernetes components...
🏄  Done! kubectl is now configured to use "minikube" cluster
```

**Comandos de ciclo de vida que você usará o curso inteiro:**

```bash
minikube status    # estado do cluster
minikube stop      # para sem destruir (preserva tudo)
minikube start     # religa
minikube delete    # destrói o cluster (recomeçar do zero)
```

> **Alternativa com Kind**, para comparar:
> ```bash
> # Instalar (Linux)
> curl -Lo kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
> sudo install kind /usr/local/bin/kind && rm kind
>
> kind create cluster --name lab   # ~30 segundos
> kind get clusters
> kind delete cluster --name lab
> ```
> Repita depois as verificações da próxima seção neste cluster e observe: os componentes são os mesmos.

### 2.2.4 Verificando a saúde do cluster (kubectl get nodes, cluster-info)

**1. O cluster responde? Onde está o API server?**

```bash
kubectl cluster-info
```
```
Kubernetes control plane is running at https://127.0.0.1:32771
CoreDNS is running at https://127.0.0.1:32771/api/v1/namespaces/kube-system/...
```

**2. Os nós estão prontos?**

```bash
kubectl get nodes -o wide
```
```
NAME       STATUS   ROLES           AGE   VERSION   ...
minikube   Ready    control-plane   2m    v1.33.x
```

Um único nó, com papel `control-plane`, em estado `Ready` — nosso cluster standalone. Se aparecer `NotReady`, o kubelet ou a rede do nó têm problemas (`kubectl describe node minikube` mostra os detalhes; troubleshooting a fundo no Capítulo 9).

**3. E os componentes do control plane que estudamos?**

```bash
kubectl get pods -n kube-system
```
```
NAME                               READY   STATUS    RESTARTS
coredns-...                        1/1     Running   0
etcd-minikube                      1/1     Running   0
kube-apiserver-minikube            1/1     Running   0
kube-controller-manager-minikube   1/1     Running   0
kube-proxy-...                     1/1     Running   0
kube-scheduler-minikube            1/1     Running   0
storage-provisioner                1/1     Running   0
```

Ali estão eles, um a um: etcd, API server, scheduler, controller-manager, kube-proxy — rodando como Pods no namespace `kube-system`, exatamente como a "curiosidade" do Capítulo 1 antecipou: o Kubernetes gerencia a si mesmo.

**4. Teste de fumaça — rode algo de verdade:**

```bash
kubectl run teste --image=nginx:1.27
kubectl get pods -w         # -w = watch; acompanhe ContainerCreating → Running (Ctrl+C para sair)
kubectl delete pod teste
```

Se o Pod chegou a `Running`, todo o circuito funcionou: kubectl → API server → etcd → scheduler → kubelet → containerd → container no ar.

---

## 2.3 Primeiros comandos com kubectl

### 2.3.1 Contextos e kubeconfig

Como o kubectl soube falar com o Minikube? Pelo arquivo **`~/.kube/config`** (o *kubeconfig*), que o `minikube start` preencheu automaticamente. Ele tem três blocos:

```yaml
apiVersion: v1
kind: Config
clusters:                # PARA ONDE conectar
- name: minikube
  cluster:
    server: https://127.0.0.1:32771
    certificate-authority: /home/voce/.minikube/ca.crt
users:                   # QUEM você é (credenciais)
- name: minikube
  user:
    client-certificate: /home/voce/.minikube/profiles/minikube/client.crt
    client-key: /home/voce/.minikube/profiles/minikube/client.key
contexts:                # combinação cluster + usuário (+ namespace padrão)
- name: minikube
  context:
    cluster: minikube
    user: minikube
    namespace: default
current-context: minikube   # ← qual contexto está ativo agora
```

Um **contexto** é um apelido para a tripla *(cluster, usuário, namespace)*. É o que permite administrar vários clusters da mesma máquina — situação normal na vida real (dev, homolog, produção):

```bash
kubectl config get-contexts            # lista contextos (o * marca o ativo)
kubectl config current-context
kubectl config use-context minikube    # troca de contexto
kubectl config set-context --current --namespace=kube-system   # muda o namespace padrão
```

> **Hábito de sobrevivência**: antes de qualquer comando destrutivo, confira o contexto. Muitos acidentes famosos em produção começam com um `kubectl delete` no contexto errado. Ferramentas como `kubectx`/`kubens` e prompts que exibem o contexto atual ajudam muito.

### 2.3.2 get, describe, logs, exec

Estes quatro comandos respondem a 90% das perguntas do dia a dia. Prepare um alvo para explorar:

```bash
kubectl create deployment web --image=nginx:1.27 --replicas=2
```

**`kubectl get` — o que existe?**

```bash
kubectl get pods                        # lista resumida
kubectl get pods -o wide                # + IP e nó
kubectl get deployments,pods            # vários tipos de uma vez
kubectl get pods -n kube-system         # em outro namespace
kubectl get pods -A                     # em todos os namespaces
kubectl get pod web-xxxxx -o yaml       # o objeto completo, como está no etcd
kubectl get pods -w                     # modo watch (tempo real)
```

**`kubectl describe` — o que está acontecendo com este objeto?**
Reúne spec, status e — a parte mais valiosa — os **eventos** recentes:

```bash
kubectl describe pod web-xxxxx
```
```
...
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  30s   default-scheduler  Successfully assigned default/web-... to minikube
  Normal  Pulling    29s   kubelet            Pulling image "nginx:1.27"
  Normal  Pulled     25s   kubelet            Successfully pulled image
  Normal  Started    25s   kubelet            Started container nginx
```

Repare: os eventos narram o loop de reconciliação em ação — scheduler atribui, kubelet puxa a imagem e inicia. Quando algo der errado (imagem inexistente, falta de recursos), **é aqui que a causa aparece primeiro**.

**`kubectl logs` — o que a aplicação está dizendo?**

```bash
kubectl logs web-xxxxx                   # stdout/stderr do container
kubectl logs web-xxxxx -f               # follow (tempo real)
kubectl logs web-xxxxx --previous       # do container anterior (após um crash!)
kubectl logs deploy/web                 # direto pelo Deployment
```

> Isso reforça uma boa prática de aplicações containerizadas: **logar para stdout/stderr**, nunca para arquivos dentro do container.

**`kubectl exec` — entre no container**

```bash
kubectl exec web-xxxxx -- nginx -v            # executa um comando pontual
kubectl exec -it web-xxxxx -- /bin/sh          # shell interativo (-it)
# dentro: hostname; ps aux; exit
```

Use para diagnóstico (testar DNS, conferir arquivos montados), não para "consertar" coisas — qualquer mudança feita ali morre com o container, como provamos no laboratório 1.2.

**Bônus que completa o kit inicial:**

```bash
kubectl api-resources        # todos os tipos de recurso e suas abreviações (po, deploy, svc...)
kubectl explain pod.spec     # documentação de cada campo, direto no terminal
kubectl get events --sort-by=.lastTimestamp   # eventos do namespace em ordem
```

### 2.3.3 Modo imperativo vs. declarativo (YAML)

No Capítulo 1, a seção 1.3.3 apresentou a filosofia; agora vamos praticá-la no kubectl, que suporta os dois modos.

**Modo imperativo — ordens diretas:**

```bash
kubectl create deployment web --image=nginx:1.27
kubectl scale deployment web --replicas=5
kubectl expose deployment web --port=80
kubectl delete deployment web
```

Rápido para experimentos e ótimo para aprender — mas as ordens não deixam registro: daqui a um mês, ninguém sabe como o ambiente foi construído.

**Modo declarativo — estado desejado em arquivos:**

Crie `web.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels:
    app: web
spec:
  replicas: 2
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
        ports:
        - containerPort: 80
```

Os **quatro campos de todo manifesto**: `apiVersion` (versão da API do recurso), `kind` (tipo), `metadata` (nome, labels), `spec` (o estado desejado — cada `kind` tem a sua; use `kubectl explain`).

```bash
kubectl apply -f web.yaml     # cria OU atualiza para casar com o arquivo
kubectl get deploy web
```

Agora edite o arquivo (`replicas: 4`) e aplique de novo:

```bash
kubectl apply -f web.yaml
kubectl get pods              # 4 réplicas
kubectl diff -f web.yaml      # antes de aplicar, veja o que mudaria (hábito excelente)
```

O `apply` é **idempotente**: rode quantas vezes quiser, o resultado é o mesmo estado final. Isso permite guardar os YAML em **Git** — o ambiente inteiro vira código versionado, revisável e reproduzível. Essa ideia, levada às últimas consequências, é o **GitOps** do Capítulo 11.

**Dica que une os dois mundos** — use o imperativo como gerador de YAML:

```bash
kubectl create deployment api --image=nginx:1.27 --dry-run=client -o yaml > api.yaml
```

`--dry-run=client -o yaml` não cria nada: só imprime o manifesto, pronto para você ajustar e versionar. É assim que a maioria dos profissionais (e candidatos à certificação CKA) evita escrever YAML do zero.

**Regra do curso daqui em diante**: imperativo para explorar e depurar; **declarativo para tudo que fica**.

**Exercício de fixação 2.3**
1. No kubeconfig, o que é um contexto e por que ele existe?
2. Um Pod está em `ImagePullBackOff`. Qual dos quatro comandos (get/describe/logs/exec) revela a causa mais rápido, e onde exatamente você olharia?
3. Por que `kubectl apply -f` executado duas vezes seguidas não causa erro nem duplica recursos?
4. Gere com `--dry-run=client -o yaml` o manifesto de um Deployment `httpd` (imagem `httpd:2.4`, 3 réplicas), salve em arquivo, aplique e comprove as 3 réplicas rodando.

---

## Laboratório consolidado do capítulo

Roteiro completo, do zero ao estado limpo (~20 min):

```bash
# 1. Cluster
minikube start --driver=docker
kubectl get nodes && kubectl get pods -n kube-system

# 2. Deploy declarativo
kubectl create deployment web --image=nginx:1.27 --replicas=2 \
  --dry-run=client -o yaml > web.yaml
kubectl apply -f web.yaml

# 3. Investigação
kubectl get pods -o wide
kubectl describe pod -l app=web | grep -A8 Events
kubectl logs deploy/web
kubectl exec -it deploy/web -- /bin/sh -c 'hostname && exit'

# 4. Escala declarativa
sed -i 's/replicas: 2/replicas: 4/' web.yaml
kubectl diff -f web.yaml
kubectl apply -f web.yaml && kubectl get pods -w   # Ctrl+C após 4 Running

# 5. Self-healing (reveja a teoria 1.3.3 acontecendo)
kubectl delete pod -l app=web --wait=false && kubectl get pods -w   # novos Pods nascem sozinhos

# 6. Limpeza
kubectl delete -f web.yaml
minikube stop
```

---

## Resumo do capítulo

- **Minikube, Kind, k3s e MicroK8s** entregam o mesmo Kubernetes por caminhos diferentes: VM/container gerenciado, containers-como-nós, ou instalação direta no SO. Escolha pela finalidade: curso → Minikube; CI → Kind; edge/homelab → k3s; Ubuntu → MicroK8s.
- O **kubectl** é universal: um só cliente para qualquer cluster, guiado pelo **kubeconfig** e seus **contextos** — confira sempre o contexto ativo antes de agir.
- A verificação de saúde básica é `cluster-info` + `get nodes` + `get pods -n kube-system`, onde você enxerga os componentes do Capítulo 1 rodando como Pods.
- **get / describe / logs / exec** formam o kit de investigação essencial — e os *Events* do describe são o primeiro lugar para procurar causas de problemas.
- **Imperativo** serve para explorar; **declarativo (`apply -f` + YAML no Git)** é o modo profissional: idempotente, versionável, reproduzível. Use `--dry-run=client -o yaml` para gerar manifestos sem escrevê-los do zero.

**Ponte para o Capítulo 3**: o cluster está no ar e você já sabe operá-lo por fora. Agora vamos abrir a caixa dos objetos que você esteve criando — o que exatamente é um Pod, o que o Deployment faz por trás, e quais outros workloads existem.
