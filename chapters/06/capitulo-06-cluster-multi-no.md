# Capítulo 6 — Montando um cluster multi-nó (3+ nós)

> **Objetivos de aprendizagem**
> Ao final deste capítulo, você será capaz de:
> 1. Planejar a topologia de um cluster (control plane único vs. HA) e justificar a escolha.
> 2. Preparar máquinas Linux para virar nós: rede, hostname, swap, firewall, kernel e containerd.
> 3. Inicializar um control plane com `kubeadm init`, instalar o CNI (Calico) e ingressar workers com `kubeadm join`.
> 4. Validar o cluster com workloads de teste que provam o funcionamento multi-nó.
> 5. Comparar kubeadm, k3s, Kubespray e clusters gerenciados (EKS/GKE/AKS).
> 6. Operar o cluster: cordon/drain, upgrade de versão, backup/restore do etcd e ciclo de vida de nós.

> **Este é o capítulo central do curso.** Tudo que o Minikube fez por você nos Capítulos 2–5, aqui você fará com as próprias mãos — e cada peça da arquitetura do Capítulo 1 vai aparecer, nomeada, no momento em que você a instalar.

---

## 6.1 Planejamento do cluster

### 6.1.1 Topologia: 1 control plane + 2 workers vs. HA com 3 control planes

**Topologia A — 1 control plane + 2 workers (a deste curso):**

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│    cp-1     │     │  worker-1   │     │  worker-2   │
│ apiserver   │     │  kubelet    │     │  kubelet    │
│ etcd        │◀────│  kube-proxy │     │  kube-proxy │
│ scheduler   │     │  containerd │     │  containerd │
│ ctrl-mgr    │     │  [apps]     │     │  [apps]     │
└─────────────┘     └─────────────┘     └─────────────┘
```

- Mínimo que já é um cluster "de verdade": scheduler distribuindo entre nós, self-healing entre máquinas, rede inter-nós via CNI.
- **Ponto único de falha**: se `cp-1` cai, as aplicações **continuam rodando** (kubelet e containers não dependem do control plane para *seguir* executando) — mas o cluster fica "congelado": sem API, sem reagendamento, sem self-healing, sem deploys. Aceitável para estudo, dev e ambientes tolerantes a janela de recuperação.

**Topologia B — HA com 3 control planes (+ N workers):**

```
                 ┌──────────────────────┐
   kubectl ─────▶│  Load Balancer / VIP │  (HAProxy+keepalived, ou LB da nuvem)
   kubelets ────▶│   :6443              │
                 └──────┬───────────────┘
        ┌───────────────┼───────────────┐
   ┌────┴────┐     ┌────┴────┐     ┌────┴────┐
   │  cp-1   │     │  cp-2   │     │  cp-3   │   etcd "stacked":
   │ api+etcd│◀───▶│ api+etcd│◀───▶│ api+etcd│   um membro por cp,
   └─────────┘     └─────────┘     └─────────┘   consenso Raft entre eles
        └───────── workers (N) ─────────┘
```

- **Por que 3, e não 2?** O etcd usa Raft (Capítulo 1): decisões exigem **quórum = maioria**. Com 3 membros, o quórum é 2 → tolera perder 1. Com 2 membros, o quórum é 2 → perder qualquer um **trava o cluster**: dois nós de etcd são *piores* que três e não são melhores que um. Sempre ímpar: 3 tolera 1 falha; 5 toleram 2.
- Os API servers são stateless: ficam todos ativos atrás do balanceador. Scheduler e controller-manager rodam em todos, mas com **eleição de líder** — um trabalha, os outros esperam.
- Variante "external etcd" (etcd em máquinas separadas dos API servers) isola falhas, ao custo de mais 3 máquinas — território de clusters grandes.

**Decisão para o curso**: montaremos a **Topologia A com 3 máquinas** — ela cumpre o objetivo "3+ nós" com o essencial do aprendizado. A seção de laboratório indica, em um quadro, os dois únicos pontos que mudariam para a Topologia B; com uma 4ª máquina você poderá evoluir para HA como exercício avançado.

### 6.1.2 Requisitos de rede, hostname, swap e firewall

**Máquinas do laboratório** — 3 VMs (VirtualBox/KVM/Proxmox/multipass, ou 3 instâncias de nuvem, ou 3 Raspberry Pi ≥ 4 GB):

| | Mínimo | Usado no lab |
|---|---|---|
| SO | Linux com systemd | Ubuntu Server 24.04 LTS |
| CPU | 2 vCPUs (exigência do kubeadm no cp) | 2 vCPUs |
| RAM | 2 GB | 4 GB |
| Disco | 20 GB | 20 GB |
| Rede | IPs fixos, mesma sub-rede, rota entre si | 192.168.56.10/11/12 |

**Planejamento de endereçamento — decida ANTES do init (relembre 4.1.1):**

```
Rede dos nós :  192.168.56.0/24   (cp-1=.10, worker-1=.11, worker-2=.12)
Pod CIDR     :  10.244.0.0/16     (não pode colidir com nada da sua rede!)
Service CIDR :  10.96.0.0/12      (idem; é o padrão do kubeadm)
```

**Hostnames** — únicos e resolvíveis entre os nós:

```bash
# em cada máquina, o seu nome:
sudo hostnamectl set-hostname cp-1        # (worker-1, worker-2 nas outras)

# em TODAS, se não houver DNS local:
cat <<EOF | sudo tee -a /etc/hosts
192.168.56.10 cp-1
192.168.56.11 worker-1
192.168.56.12 worker-2
EOF
```

> Se as VMs foram **clonadas**, cheque também `sudo cat /sys/class/dmi/id/product_uuid` e os MACs das interfaces: o kubeadm exige que sejam únicos por nó.

**Swap — desabilite** (em todas):

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab      # persiste após reboot
```

*Por quê?* O kubelet gerencia memória com precisão via requests/limits e cgroups (Capítulo 7); com swap, "memória cheia" vira "lentidão imprevisível" em vez de um sinal claro para agir (evicção/OOM). Suporte a swap existe em versões recentes, mas desligar continua sendo o caminho padrão e o que o kubeadm espera.

**Firewall — portas entre os nós:**

| Porta(s) | Onde | Quem usa |
|---|---|---|
| 6443/tcp | control plane | API server (todos falam com ele) |
| 2379-2380/tcp | control plane | etcd (cliente e peers) |
| 10250/tcp | todos | kubelet API (logs, exec, métricas) |
| 10257, 10259/tcp | control plane | controller-manager, scheduler |
| 30000-32767/tcp | workers | NodePort (Capítulo 4) |
| 179/tcp ou 4789/udp | todos | Calico (BGP ou VXLAN) |

Em laboratório na mesma sub-rede confiável, o mais simples é liberar tudo entre os três IPs (ou `sudo ufw disable` no lab). Em produção: liberar exatamente a tabela acima.

### 6.1.3 Escolha do runtime (containerd) e do CNI

**Runtime: containerd** — sem suspense, pelo que você já sabe dos Capítulos 1–2: é o padrão de fato pós-dockershim, leve, estável, e é o que roda por baixo até do Docker. (CRI-O seria a alternativa equivalente; a escolha muda pouco na prática.)

Um detalhe **crítico** que derruba muitos clusters de iniciantes: o **cgroup driver**. Kubelet e containerd precisam usar o **mesmo** gerenciador de cgroups, e em distribuições com systemd o correto é **`SystemdCgroup = true`** na configuração do containerd (o kubelet moderno já assume systemd). Sintoma clássico do desalinhamento: nós que entram e caem, kubelet reiniciando em loop. O laboratório configura isso explicitamente.

**CNI: Calico** — pelos critérios do Capítulo 4: pronto para produção, suporta **NetworkPolicies** (pré-requisito do Capítulo 8, que o Flannel não atende) e funciona bem em bare metal/VMs com BGP ou VXLAN. (Cilium seria a escolha "moderna"; fica como variação sugerida ao final do capítulo.)

**Exercício de fixação 6.1**
1. O control plane único do nosso cluster caiu. Liste duas coisas que continuam funcionando e três que param — e explique pela arquitetura do Capítulo 1.
2. Por que um etcd com 4 membros não tolera mais falhas que um com 3? Faça a conta do quórum.
3. Sua rede corporativa usa `10.244.0.0/16` para as estações de trabalho. Que problema isso causa no cluster do lab e qual a correção?
4. Explique, em uma frase cada, por que: (a) swap fica desligado; (b) o cgroup driver precisa estar alinhado; (c) escolhemos Calico e não Flannel.

---

## 6.2 Bootstrap com kubeadm (laboratório principal)

O **kubeadm** é a ferramenta oficial de bootstrap: ele não cria máquinas nem instala pacotes — ele transforma máquinas preparadas em cluster, cuidando do que é difícil (certificados TLS de todos os componentes, manifestos estáticos do control plane, tokens de ingresso).

### 6.2.1 Preparação dos nós (kernel modules, sysctl, containerd)

**Execute esta seção inteira NAS TRÊS máquinas.** (Dica de eficiência: monte um script `prepara-no.sh` com tudo — primeiro passo rumo à automação da seção 6.3.2.)

```bash
# ── 1. Módulos de kernel ──────────────────────────────────────────────
# overlay: filesystem de camadas das imagens (Capítulo 1)
# br_netfilter: tráfego de bridge visível ao iptables (Services!)
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay && sudo modprobe br_netfilter

# ── 2. Parâmetros de rede do kernel ──────────────────────────────────
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# ── 3. containerd ─────────────────────────────────────────────────────
sudo apt-get update && sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
# o ajuste crítico da seção 6.1.3:
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd && sudo systemctl enable containerd

# ── 4. kubeadm, kubelet, kubectl (repositório oficial) ───────────────
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl    # ← upgrades só de forma controlada (6.4.2)!
```

> O kubelet ficará reiniciando em loop até o `kubeadm init/join` — é esperado: ele aguarda sua configuração nascer.

### 6.2.2 kubeadm init no control plane

**Apenas em `cp-1`:**

```bash
sudo kubeadm init \
  --apiserver-advertise-address=192.168.56.10 \
  --pod-network-cidr=10.244.0.0/16 \
  --control-plane-endpoint=cp-1:6443
```

- `--apiserver-advertise-address`: o IP em que o API server escuta (importante em VMs com múltiplas interfaces — use o IP da rede dos nós!).
- `--pod-network-cidr`: o Pod CIDR planejado em 6.1.2; o CNI precisará casar com ele.
- `--control-plane-endpoint`: um **nome** para o control plane. Hoje resolve para cp-1; se um dia você migrar para HA, esse nome passa a apontar para o load balancer **sem re-emitir certificados** — é a porta deixada aberta para a Topologia B.

**O que o init faz (acompanhe na saída — é o Capítulo 1 se materializando):**

1. *preflight*: valida a máquina (CPUs, portas, swap, containerd);
2. *certs*: gera a CA do cluster e os certificados de todos os componentes em `/etc/kubernetes/pki`;
3. *kubeconfig*: credenciais de admin e dos componentes;
4. *control-plane*: escreve os **static pod manifests** em `/etc/kubernetes/manifests/` — e o kubelet, que vigia essa pasta, sobe apiserver, etcd, scheduler e controller-manager *como Pods* (a "curiosidade" do Capítulo 1, agora sob seus dedos: `ls /etc/kubernetes/manifests/`);
5. *bootstrap-token* + instruções de `join`.

**Guarde as três coisas que a saída entrega:**

```bash
# 1) Configure seu kubectl no cp-1:
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 2) O comando de join dos workers (copie o SEU, com token e hash reais):
#    kubeadm join cp-1:6443 --token abcdef.0123456789abcdef \
#        --discovery-token-ca-cert-hash sha256:xxxx...

# 3) Se perder o join, gere outro a qualquer momento:
kubeadm token create --print-join-command
```

**Primeiro contato — e o estado esperado é "quebrado":**

```bash
kubectl get nodes
# NAME   STATUS     ROLES           ...
# cp-1   NotReady   control-plane
kubectl get pods -n kube-system
# coredns-...   0/1   Pending
```

`NotReady` e CoreDNS `Pending` — exatamente como o Capítulo 4 previu: **sem CNI, Pods não ganham rede**. Você está vendo a dependência com os próprios olhos.

### 6.2.3 Instalando o plugin de rede (CNI)

Instalaremos o **Calico** via seu operator (aliás: seu primeiro contato prático com um Operator, tema do Capítulo 10):

```bash
# 1. O operator do Calico (verifique a versão atual na documentação do projeto)
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.0/manifests/tigera-operator.yaml

# 2. A configuração da instalação — o CIDR TEM que casar com o --pod-network-cidr:
cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - cidr: 10.244.0.0/16
      encapsulation: VXLAN        # opção robusta p/ VMs de lab; BGP é a alternativa
EOF

# 3. Aguarde e colha o resultado
watch kubectl get pods -A          # calico-* Running, coredns Running... (Ctrl+C)
kubectl get nodes                  # cp-1   Ready   ✔
```

A sequência `NotReady → instala CNI → Ready` é uma das lições mais valiosas do curso: agora você sabe **o que** o Minikube fazia por você e **onde** procurar quando a rede de um cluster real falhar.

### 6.2.4 kubeadm join dos workers

**Em `worker-1` e `worker-2`** (que já passaram pela preparação 6.2.1), cole o comando guardado:

```bash
sudo kubeadm join cp-1:6443 --token <seu-token> \
  --discovery-token-ca-cert-hash sha256:<seu-hash>
```

O que acontece: o worker localiza o API server, **valida a CA do cluster pelo hash** (por isso ele existe: impede ingressar no cluster errado ou num impostor), autentica-se com o token temporário, e o kubelet solicita seu próprio certificado (TLS bootstrap). O Calico, cujos componentes por nó rodam como **DaemonSet** (Capítulo 3!), povoa o novato automaticamente.

**De volta ao cp-1:**

```bash
kubectl get nodes -o wide
# NAME       STATUS   ROLES           VERSION
# cp-1       Ready    control-plane   v1.33.x
# worker-1   Ready    <none>          v1.33.x
# worker-2   Ready    <none>          v1.33.x

kubectl label node worker-1 node-role.kubernetes.io/worker=   # cosmético, p/ ROLES
kubectl label node worker-2 node-role.kubernetes.io/worker=
```

**Três nós. Cluster de verdade, montado por você.**

> **Se fosse a Topologia B (HA):** os dois únicos acréscimos seriam (1) `--control-plane-endpoint` apontando para o VIP/LB desde o início e `--upload-certs` no init; (2) nos demais control planes, o join ganharia `--control-plane --certificate-key <chave>`. Todo o resto é idêntico.

> **E onde ficou o kubeconfig?** Copie `/etc/kubernetes/admin.conf` do cp-1 para a sua estação (`~/.kube/config` ou via `KUBECONFIG`) e administre o cluster de fora — com a ressalva de que o admin.conf é a "chave mestra"; credenciais individuais com menos poder são tema do RBAC, no Capítulo 8.

### 6.2.5 Validando o cluster com workloads de teste

Não basta `Ready`; prove cada capacidade:

```bash
# ── Teste 1: o scheduler espalha entre nós ───────────────────────────
kubectl create deploy valida --image=nginxdemos/hello:plain-text --replicas=6
kubectl get pods -o wide          # réplicas distribuídas entre worker-1 e worker-2
# Note: NADA no cp-1 — o kubeadm aplica um taint ao control plane (o Capítulo 7
# explica a mecânica): kubectl describe node cp-1 | grep Taint

# ── Teste 2: rede Pod-a-Pod ENTRE nós (a promessa do modelo de rede) ─
kubectl get pods -o wide          # escolha dois Pods em nós DIFERENTES
kubectl exec <pod-no-worker-1> -- wget -qO- http://<IP-do-pod-no-worker-2>

# ── Teste 3: Service + DNS no cluster novo ───────────────────────────
kubectl expose deploy valida --port=80
kubectl run cliente --rm -it --image=busybox:1.36 -- \
  sh -c 'nslookup valida && wget -qO- http://valida | grep -i name'

# ── Teste 4: NodePort respondendo por QUALQUER nó ────────────────────
kubectl expose deploy valida --port=80 --type=NodePort --name=valida-np
kubectl get svc valida-np                       # porta 3xxxx
curl http://192.168.56.11:<porta>/ && curl http://192.168.56.12:<porta>/

# ── Teste 5: o grande final — self-healing entre MÁQUINAS ────────────
# Desligue worker-2 (poweroff da VM). Aguarde ~5 min (detecção + tolerância padrão).
kubectl get nodes -w                            # worker-2 NotReady
kubectl get pods -o wide -w                     # Pods dele: Terminating → novos no worker-1
# Religue worker-2: ele volta a Ready e ao jogo. A cena do Capítulo 1, ao vivo.

kubectl delete deploy valida && kubectl delete svc valida valida-np
```

> **Peças que o cluster kubeadm NÃO traz** (e o Minikube trazia): StorageClass default (instale um provisioner, ex.: local-path-provisioner ou NFS CSI — sem isso os PVCs do Capítulo 5 ficam Pending), Ingress Controller (instale o Ingress-NGINX por manifesto/Helm), metrics-server (Capítulo 7) e LoadBalancer (MetalLB, se quiser IPs externos em bare metal). Instalar cada uma é excelente exercício de revisão dos capítulos anteriores.

**Exercício de fixação 6.2**
1. Reconte as 5 fases do `kubeadm init` e aponte, em cada uma, o componente do Capítulo 1 envolvido.
2. Para que serve o `--discovery-token-ca-cert-hash` no join? Que ataque ele previne?
3. Um colega rodou o init sem `--pod-network-cidr` e o Calico não funciona. Onde está o descasamento e como diagnosticá-lo?
4. No Teste 5, por que os Pods do worker-2 demoraram ~5 minutos para serem realocados? (Guarde a resposta: o Capítulo 7 mostra como ajustar essas tolerâncias.)

---

## 6.3 Alternativas de instalação

O kubeadm ensina como o cluster funciona — mas não é o único caminho, e conhecer o cardápio faz parte de dominar o assunto.

### 6.3.1 k3s multi-nó

O k3s do Capítulo 2 escala para multi-nó com uma facilidade desconcertante:

```bash
# No servidor (control plane):
curl -sfL https://get.k3s.io | sh -
sudo cat /var/lib/rancher/k3s/server/node-token     # o "join token" do k3s

# Em cada agente (worker):
curl -sfL https://get.k3s.io | \
  K3S_URL=https://192.168.56.10:6443 K3S_TOKEN=<node-token> sh -
```

Pronto — e com Traefik (Ingress), storage local (local-path) e LoadBalancer (ServiceLB) **já inclusos**, exatamente as peças que o kubeadm deixa por sua conta. HA também é simples (`--cluster-init` + servidores adicionais, com etcd embutido).
**Trade-off**: você ganha produtividade e perde a visibilidade das entranhas — ótimo *depois* de ter aprendido com o kubeadm, e excelente para homelab, edge e produção enxuta.

### 6.3.2 Kubespray (visão geral)

Notou quanto trabalho manual repetido houve na seção 6.2.1? O **Kubespray** é a resposta da comunidade: um projeto **Ansible** que automatiza tudo — preparação dos nós, containerd, kubeadm (ele usa kubeadm por baixo!), CNI à escolha, HA, upgrades — a partir de um inventário declarativo das suas máquinas:

```
inventory/meucluster/hosts.yaml  →  ansible-playbook cluster.yml  →  cluster pronto
```

É a ponte entre "montei na mão" e "infraestrutura como código": clusters **reproduzíveis** de dezenas ou centenas de nós on-prem. Alternativas no mesmo espaço: **RKE2** (o irmão "enterprise/hardened" do k3s), **Talos Linux** (SO imutável feito só para Kubernetes) e **Cluster API** (o Kubernetes provisionando clusters Kubernetes).

### 6.3.3 Clusters gerenciados: EKS, GKE, AKS (comparativo)

Nas nuvens, o **control plane vira serviço**: AWS (EKS), Google (GKE) e Azure (AKS) operam API server, etcd (com backups!), upgrades e HA por você — restam os workers (e no GKE Autopilot, nem isso).

| | Você gerencia (kubeadm) | Gerenciado (EKS/GKE/AKS) |
|---|---|---|
| Control plane, etcd, certificados | você | o provedor |
| Upgrades do control plane | você (6.4.2) | um clique/automático |
| Workers | você | você (ou node pools automáticos) |
| Integrações (LB, discos, IAM) | você instala (MetalLB, CSI...) | nativas |
| Custo | máquinas + seu tempo | taxa do control plane + máquinas |
| Controle/customização | total | limitado ao exposto |
| Onde roda | onde você quiser | na nuvem do provedor |

**A lição de carreira**: no mercado, a maioria dos clusters de produção é gerenciada — e é aí que seu conhecimento de kubeadm vira diferencial, não desperdício: quando o cluster gerenciado apresentar um Pod `Pending`, um nó `NotReady` ou um DNS falhando, quem sabe *o que existe por baixo* diagnostica; quem só clicou no console, não. E dentro do cluster (Capítulos 3–5, 7–11), **tudo é idêntico**.

**Exercício de fixação 6.3**
1. Em quais cenários você recomendaria: kubeadm puro, k3s, Kubespray, EKS? Um critério decisivo para cada.
2. O Kubespray usa kubeadm internamente. O que ele agrega, então? Relacione com a seção 6.2.1.
3. "Se vou usar EKS na empresa, aprender kubeadm foi perda de tempo." Refute com dois argumentos técnicos.

---

## 6.4 Operações essenciais do cluster

Montar é o dia 1; **operar é todo dia**. As quatro operações a seguir são o kit de sobrevivência (e presença garantida na certificação CKA).

### 6.4.1 Cordon, drain e manutenção de nós

Manutenção de um nó (patch de kernel, troca de disco, reboot) sem derrubar aplicações:

```bash
# 1. CORDON: marca o nó como não-agendável (Pods atuais ficam; novos não entram)
kubectl cordon worker-1
kubectl get nodes                        # worker-1  Ready,SchedulingDisabled

# 2. DRAIN: despeja os Pods (que os controllers recriam nos OUTROS nós) e mantém o cordon
kubectl drain worker-1 --ignore-daemonsets --delete-emptydir-data
#   --ignore-daemonsets: DaemonSets (Calico, kube-proxy) não têm para onde ir — ficam
#   --delete-emptydir-data: consente perder emptyDirs (efêmeros por definição, Capítulo 5)

kubectl get pods -o wide                 # tudo realocado; worker-1 vazio

# 3. Faça a manutenção (apt upgrade, reboot...)

# 4. UNCORDON: devolve o nó ao jogo
kubectl uncordon worker-1                # novos agendamentos voltam a considerá-lo
```

Repare no contraste com o Teste 5 da validação: lá, a queda **abrupta** custou ~5 minutos de limbo; aqui, o drain **gracioso** realoca tudo em segundos, respeitando o encerramento limpo (SIGTERM, Capítulo 1). *Planejado > acidental.*
(O drain respeita também os **PodDisruptionBudgets** — a trava que impede despejar réplicas demais ao mesmo tempo. Capítulo 7.)

### 6.4.2 Upgrade de versão com kubeadm

Regras do jogo: upgrades **minor por minor** (1.33 → 1.34; nunca pular), **control plane primeiro**, depois workers, um a um. O `apt-mark hold` da preparação existe para este momento: nada atualiza sem você mandar.

**No control plane:**

```bash
# 1. Aponte o repositório APT para a série nova (v1.34) e:
sudo apt-mark unhold kubeadm && sudo apt-get update
sudo apt-get install -y kubeadm=1.34.x-* && sudo apt-mark hold kubeadm

# 2. Planeje (mostra versões possíveis e o que será feito) e aplique:
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.34.x       # renova manifests estáticos e certificados

# 3. kubelet e kubectl do nó (com drain, como aprendido):
kubectl drain cp-1 --ignore-daemonsets
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.34.x-* kubectl=1.34.x-*
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload && sudo systemctl restart kubelet
kubectl uncordon cp-1
```

**Em cada worker, um por vez** (o cluster segue servindo nos demais — eis o valor do multi-nó):

```bash
kubectl drain worker-1 --ignore-daemonsets --delete-emptydir-data   # do cp-1
# no worker-1:
sudo apt-mark unhold kubeadm && sudo apt-get update && \
  sudo apt-get install -y kubeadm=1.34.x-* && sudo apt-mark hold kubeadm
sudo kubeadm upgrade node
sudo apt-mark unhold kubelet && sudo apt-get install -y kubelet=1.34.x-* && sudo apt-mark hold kubelet
sudo systemctl daemon-reload && sudo systemctl restart kubelet
# do cp-1:
kubectl uncordon worker-1
kubectl get nodes        # confira a versão antes de partir para o worker-2
```

> **Antes de qualquer upgrade: backup do etcd** (próxima seção) e leitura das *release notes* — APIs são descontinuadas em versões novas e manifestos antigos podem precisar de ajuste.

### 6.4.3 Backup e restore do etcd

O Capítulo 1 avisou: *perdeu o etcd sem backup, perdeu o cluster* — todos os objetos, todos os namespaces, tudo. Esta é a rotina que não pode faltar.

**Backup (no cp-1; o etcd escuta em localhost com mTLS):**

```bash
sudo ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-$(date +%F-%H%M).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

sudo etcdctl snapshot status /backup/etcd-*.db --write-out=table   # valide!
```

Automatize (um cron/systemd-timer no cp-1) e **copie para fora do nó**: backup que mora junto do desastre não é backup. Guarde também `/etc/kubernetes/pki` (a CA e os certificados).

**Restore (o dia D):**

```bash
# 1. Pare o control plane movendo os static manifests (o kubelet os derruba):
sudo mv /etc/kubernetes/manifests /etc/kubernetes/manifests.off

# 2. Restaure o snapshot para um diretório NOVO:
sudo etcdctl snapshot restore /backup/etcd-2026-08-09.db \
  --data-dir=/var/lib/etcd-restaurado

# 3. Aponte o manifest do etcd para o novo diretório:
#    edite o etcd.yaml (em manifests.off) → hostPath /var/lib/etcd-restaurado

# 4. Religue tudo:
sudo mv /etc/kubernetes/manifests.off /etc/kubernetes/manifests
watch kubectl get pods -n kube-system     # o cluster "volta no tempo" do snapshot
```

**Treine o restore.** Em um cluster de estudo: crie objetos, faça snapshot, delete objetos, restaure e veja-os voltar. Backup nunca testado é uma esperança, não um plano.

> Nota de escopo: o snapshot do etcd salva os **objetos** do cluster, não os **dados nos PVs** (Capítulo 5) — esses pedem backup próprio (do storage, ou ferramentas como o Velero, que cobre os dois mundos).

### 6.4.4 Adicionando e removendo nós

**Adicionar** — você já sabe: prepare a máquina (6.2.1) e:

```bash
kubeadm token create --print-join-command     # tokens expiram em 24h — gere um novo
# rode o join no nó novo; o Calico (DaemonSet) o adota sozinho
```

É assim que o cluster cresce de 3 para 30 nós: o procedimento é **o mesmo** (e é o que autoscalers de nós fazem por baixo, na nuvem).

**Remover — na ordem certa, sempre:**

```bash
# 1. Esvazie com respeito (as apps migram):
kubectl drain worker-2 --ignore-daemonsets --delete-emptydir-data

# 2. Remova do cluster:
kubectl delete node worker-2

# 3. No próprio nó (se for reaproveitá-lo), limpe a identidade antiga:
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d ~/.kube      # sobras de CNI e credenciais
```

Pular o drain (deletar o nó com Pods dentro) força o caminho da falha abrupta — funciona, mas com o custo e o risco que o Teste 5 mostrou. **Drain primeiro** é o hábito.

**Exercício de fixação 6.4**
1. Diferencie cordon de drain. Em que situação usar só o cordon faz sentido?
2. Por que `--ignore-daemonsets` é necessário no drain? O que acontece com o Calico daquele nó, e por que tudo bem?
3. Monte o runbook resumido (comandos na ordem) para atualizar o cluster de 1.33 para 1.34 com zero downtime das aplicações. Onde entra o backup?
4. Após um `kubeadm reset` malfeito, um nó re-ingressado apresenta erros de rede. Que diretório provavelmente ficou sujo?
5. Desafio: transforme o backup do etcd em um CronJob diário (Capítulo 3) que grava em um PVC (Capítulo 5). Que cuidados de segurança esse Pod exige? (Reflexão que o Capítulo 8 aprofunda.)

---

## Laboratório consolidado do capítulo

O próprio capítulo é o laboratório. Checklist de conclusão — marque apenas o que **executou e entendeu**:

- [ ] 3 máquinas preparadas (script `prepara-no.sh` versionado)
- [ ] `kubeadm init` com CIDRs planejados e `--control-plane-endpoint`
- [ ] Vi o cluster `NotReady` → instalei o Calico → `Ready`
- [ ] 2 workers ingressados via `kubeadm join`
- [ ] Testes 1–5 de validação (scheduler, rede inter-nós, DNS, NodePort, self-healing com queda de nó)
- [ ] Peças extras instaladas: storage provisioner + Ingress-NGINX (revisão dos Capítulos 4–5)
- [ ] Ciclo completo de manutenção: cordon → drain → reboot → uncordon
- [ ] Upgrade minor do cluster inteiro, nó a nó
- [ ] Snapshot do etcd + **restore testado**
- [ ] Nó removido com drain + reset, e re-adicionado com token novo

**Extensões sugeridas**: (a) 4ª máquina → converta para HA (Topologia B); (b) refaça tudo com k3s e cronometre a diferença; (c) troque Calico por Cilium e explore o Hubble; (d) escreva seu runbook pessoal de operações — ele será ouro no Capítulo 9.

---

## Resumo do capítulo

- **Topologia**: 1 control plane + workers é um cluster real com um ponto único de falha *de gestão* (as apps sobrevivem à queda dele); HA exige **3** control planes por causa do **quórum do Raft** (sempre ímpar).
- **Preparação de nó**: hostname único, swap off, portas liberadas, módulos `overlay`/`br_netfilter`, sysctl de forwarding, containerd com **SystemdCgroup=true**, pacotes em **hold**.
- **Bootstrap**: `kubeadm init` (certificados, static pods, token) → cluster nasce `NotReady` → **CNI (Calico)** dá rede e vida → `kubeadm join` traz os workers, validando a CA pelo hash.
- **Validação** é ativa: scheduler espalhando, Pod-a-Pod entre nós, DNS, NodePort em qualquer nó e self-healing com queda real de máquina. kubeadm não traz storage/Ingress/metrics/LB — você instala.
- **Alternativas**: k3s (produtividade, baterias inclusas), Kubespray (kubeadm + Ansible = reproduzível em escala), gerenciados (control plane como serviço — e seu kubeadm vira vantagem de diagnóstico).
- **Operação**: **cordon/drain/uncordon** para manutenção graciosa; **upgrade** minor a minor, control plane primeiro, nó a nó; **etcd**: snapshot rotineiro, guardado fora do nó e com **restore treinado**; nós entram com token novo e saem com drain + delete + reset.

**Ponte para o Capítulo 7**: seu cluster multi-nó está vivo — e novas perguntas surgem exatamente por haver múltiplos nós: por que nada agenda no control plane (o tal *taint*)? Como garantir que um Pod tenha os recursos de que precisa, ou que réplicas não caiam juntas no mesmo nó? Como escalar sob demanda? Scheduling, recursos e autoscaling são o próximo assunto.
