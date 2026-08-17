# Capítulo 1 — Fundamentos e contexto

> **Objetivos de aprendizagem**
> Ao final deste capítulo, você será capaz de:
> 1. Explicar a evolução da infraestrutura (bare metal → VMs → containers) e o que motivou cada salto.
> 2. Descrever os problemas operacionais que um orquestrador de containers resolve.
> 3. Diferenciar Docker, containerd e CRI-O, e explicar o papel do padrão OCI.
> 4. Descrever o ciclo de vida de uma imagem e de um container.
> 5. Desenhar de memória a arquitetura do Kubernetes, nomeando os componentes do control plane e dos nós de trabalho.
> 6. Explicar o modelo declarativo e o loop de reconciliação — o "coração" do Kubernetes.

---

## 1.1 Por que Kubernetes existe

### 1.1.1 Do bare metal às VMs e aos containers

**Era 1 — Bare metal (anos 1990–2000).**
Cada aplicação rodava diretamente sobre um servidor físico. Esse modelo trazia problemas crônicos:

- **Subutilização**: para garantir desempenho nos picos, os servidores eram superdimensionados e passavam a maior parte do tempo ociosos (utilização típica de 10–20%).
- **Isolamento fraco**: colocar duas aplicações no mesmo servidor significava disputar bibliotecas, portas e recursos. Uma falha derrubava a outra.
- **Provisionamento lento**: adicionar capacidade envolvia comprar, instalar e configurar hardware — semanas ou meses.

**Era 2 — Virtualização (anos 2000–2010).**
Hipervisores (VMware, Xen, KVM) permitiram fatiar um servidor físico em várias **máquinas virtuais**, cada uma com seu próprio sistema operacional. Ganhos:

- Melhor aproveitamento do hardware.
- Isolamento forte entre aplicações.
- Provisionamento em minutos, não semanas — a base da computação em nuvem (a AWS EC2 nasce em 2006).

Mas cada VM carrega um **sistema operacional completo**: gigabytes de disco, centenas de MB de RAM só para o SO, e boot de dezenas de segundos. Rodar 50 microsserviços em 50 VMs significa manter 50 kernels.

**Era 3 — Containers (2013 em diante).**
Containers usam recursos do próprio kernel Linux para isolar processos, **sem** virtualizar hardware nem duplicar o sistema operacional:

- **Namespaces**: dão a cada container sua própria visão de processos, rede, sistema de arquivos, usuários e hostname.
- **Cgroups (control groups)**: limitam quanto de CPU, memória e I/O cada container pode consumir.
- **Union filesystems** (overlayfs): permitem empilhar camadas de imagem de forma eficiente, compartilhando o que é comum.

Essas tecnologias existiam no kernel muito antes (e o conceito é ainda mais antigo — chroot, FreeBSD jails, Solaris Zones, LXC). A revolução do **Docker, em 2013**, foi de *experiência de uso*: um formato de imagem portátil, um Dockerfile simples e um registry público (Docker Hub). Pela primeira vez, "funciona na minha máquina" passou a significar "funciona em qualquer máquina".

**Comparativo resumido:**

| Característica | Bare metal | VM | Container |
|---|---|---|---|
| Isolamento | Nenhum (mesmo SO) | Forte (hipervisor) | Bom (kernel compartilhado) |
| Overhead | — | SO completo por VM | Apenas o processo |
| Tempo de inicialização | Minutos (boot físico) | Dezenas de segundos | Milissegundos a segundos |
| Densidade por servidor | 1 app | Dezenas de VMs | Centenas de containers |
| Portabilidade | Baixa | Média (imagens grandes) | Alta (imagens em camadas, padrão OCI) |

> **Nota importante**: containers e VMs não são rivais excludentes. Na prática, a maioria dos clusters Kubernetes em nuvem roda containers *dentro* de VMs, combinando o isolamento forte da virtualização com a agilidade dos containers.

### 1.1.2 Problemas que a orquestração resolve (escala, resiliência, deploy)

Containers resolvem o empacotamento e a portabilidade de **uma** aplicação. Mas o que acontece quando você tem **centenas de containers em dezenas de servidores**? Surge uma nova classe de perguntas:

**Agendamento (scheduling)**
- Em qual servidor cada container deve rodar?
- Como distribuir a carga considerando CPU e memória disponíveis?
- Como evitar que duas réplicas do mesmo serviço caiam juntas no mesmo servidor?

**Escala**
- Como aumentar de 3 para 30 réplicas quando o tráfego cresce — e voltar para 3 quando ele cai?
- Como fazer isso automaticamente, com base em métricas?

**Resiliência (self-healing)**
- Se um container trava, quem o reinicia?
- Se um servidor inteiro morre às 3h da manhã, quem realoca os containers dele para os servidores saudáveis?
- Como detectar que uma aplicação está "viva, mas não saudável" (ex.: em deadlock)?

**Deploy**
- Como atualizar 30 réplicas para uma nova versão **sem downtime**?
- Como reverter rapidamente se a nova versão apresentar erros?
- Como testar a nova versão com uma fração do tráfego antes de liberar para todos?

**Rede e descoberta de serviços**
- Se containers nascem e morrem o tempo todo, com IPs efêmeros, como o serviço A encontra o serviço B?
- Como balancear tráfego entre as réplicas?

**Configuração e segredos**
- Como injetar configurações e senhas sem embuti-las na imagem?

Fazer tudo isso manualmente (ou com scripts shell) não escala. Um **orquestrador de containers** é o sistema que responde a todas essas perguntas de forma automatizada. O Kubernetes — lançado pelo Google em 2014, inspirado nos sistemas internos Borg e Omega, e doado à CNCF (Cloud Native Computing Foundation) em 2015 — venceu a "guerra dos orquestradores" (contra Docker Swarm e Apache Mesos) e se tornou o padrão de fato da indústria.

> **Quando NÃO usar Kubernetes**: um site pequeno, uma aplicação monolítica estável com pouco tráfego ou um time sem maturidade operacional podem ser mais bem servidos por soluções mais simples (um único servidor, PaaS como Heroku/Fly.io, ou serviços gerenciados de container como Cloud Run/ECS Fargate). Kubernetes resolve problemas de escala e complexidade — se você não os tem, ele *adiciona* complexidade.

**Exercício de fixação 1.1**
1. Cite duas vantagens dos containers sobre VMs e uma vantagem das VMs sobre containers.
2. Sua empresa tem 5 microsserviços rodando em 3 servidores, gerenciados por scripts shell. Liste três problemas que tendem a aparecer quando esse número crescer para 50 microsserviços em 20 servidores.

---

## 1.2 Revisão rápida de containers

### 1.2.1 Docker / containerd / CRI-O e o padrão OCI

O termo "Docker" costuma causar confusão porque se refere, ao mesmo tempo, a uma empresa, uma ferramenta de linha de comando e um daemon. Vamos separar as peças.

**O padrão OCI (Open Container Initiative)**
Criado em 2015 para evitar a fragmentação do ecossistema, o OCI define três especificações:

- **image-spec**: o formato das imagens de container (camadas + manifesto + configuração).
- **runtime-spec**: como executar um container a partir de um bundle extraído.
- **distribution-spec**: como registries distribuem imagens (push/pull via HTTP).

Graças ao OCI, uma imagem construída com qualquer ferramenta (Docker, Buildah, Kaniko) roda em qualquer runtime compatível. **Isso é o que torna o ecossistema intercambiável.**

**As camadas de runtime**

```
┌─────────────────────────────────────────────┐
│  Ferramenta do usuário (podman CLI, nerdctl)│  ← experiência do desenvolvedor
├─────────────────────────────────────────────┤
│  Runtime de alto nível (containerd, CRI-O)  │  ← gerencia imagens, storage, ciclo de vida
├─────────────────────────────────────────────┤
│  Runtime de baixo nível (runc, crun, kata)  │  ← cria de fato o container (namespaces, cgroups)
├─────────────────────────────────────────────┤
│  Kernel Linux                               │
└─────────────────────────────────────────────┘
```

- **runc**: runtime de baixo nível de referência do OCI. É ele quem efetivamente chama o kernel para criar namespaces e cgroups. Praticamente todo o ecossistema o usa por baixo.
- **containerd**: runtime de alto nível. Baixa imagens, gerencia camadas e snapshots, supervisiona containers e delega a criação ao runc. Nasceu dentro do Docker e foi doado à CNCF. **É o runtime mais usado em clusters Kubernetes hoje.**
- **CRI-O**: runtime de alto nível criado especificamente para o Kubernetes (projeto ligado à Red Hat; é o padrão no OpenShift). Implementa exatamente o que o Kubernetes precisa, nada mais.
- **Docker (Engine)**: a plataforma completa para desenvolvedores — CLI + API + daemon (que, internamente, usa containerd + runc). Excelente para desenvolvimento local.

**E a famosa "remoção do Docker" do Kubernetes?**
O Kubernetes conversa com o runtime através de uma interface padronizada, a **CRI (Container Runtime Interface)**. O Docker Engine nunca implementou a CRI nativamente, então o Kubernetes mantinha um adaptador interno chamado *dockershim* — removido na versão 1.24 (2022). Na prática, os clusters passaram a falar **diretamente com o containerd** (o mesmo componente que o Docker já usava por baixo). Consequência importante para você: **imagens construídas com Docker continuam funcionando perfeitamente**, pois são imagens OCI. O que mudou foi apenas quem as executa no nó.

### 1.2.2 Imagens, registries e o ciclo de vida de um container

**Imagem** é um pacote imutável e portátil contendo tudo o que a aplicação precisa: binários, bibliotecas, arquivos e metadados (comando de inicialização, variáveis de ambiente, portas expostas).

- Imagens são formadas por **camadas** empilhadas e somente leitura. Cada instrução relevante do Dockerfile (`FROM`, `RUN`, `COPY`) gera uma camada.
- Camadas são **compartilhadas**: se 10 imagens usam a mesma base `debian:12`, essa base ocupa espaço uma única vez no disco e no cache do nó.
- Ao executar, o runtime adiciona uma fina **camada de escrita** por cima (copy-on-write). Tudo que o container gravar ali **morre com ele** — por isso a regra de ouro: *containers são efêmeros; dados persistentes vivem em volumes* (veremos no Capítulo 5).

**Nomenclatura e tags**

```
registry.exemplo.com/loja/api-pedidos:2.4.1
└──────┬───────────┘ └───┬────────┘ └─┬──┘
    registry            repositório   tag
```

- Sem registry explícito, assume-se o Docker Hub; sem tag, assume-se `latest`.
- **Cuidado com `latest`**: a tag é mutável e não significa "mais recente" — é apenas um apelido. Em produção, use tags de versão imutáveis ou o **digest** (`@sha256:...`), que identifica o conteúdo exato da imagem.

**Registry** é o serviço que armazena e distribui imagens (Docker Hub, GitHub Container Registry, Amazon ECR, Google Artifact Registry, Harbor auto-hospedado). O fluxo típico:

```
Dockerfile ──build──▶ imagem local ──push──▶ registry ──pull──▶ nós do cluster ──run──▶ container
```

**Ciclo de vida de um container**

1. **Created**: o runtime preparou o filesystem e a configuração, mas o processo ainda não iniciou.
2. **Running**: o processo principal (PID 1 do container) está em execução.
3. **Paused** (opcional): processos congelados via cgroup freezer.
4. **Stopped/Exited**: o processo principal terminou — com código `0` (sucesso) ou diferente de zero (erro). *Quando o PID 1 morre, o container morre.*
5. **Removed**: container e sua camada de escrita são destruídos.

Dois detalhes desse ciclo são fundamentais para entender o Kubernetes depois:

- **O código de saída** é como o Kubernetes decide se um container "falhou" e se deve reiniciá-lo (você verá muito o estado `CrashLoopBackOff` no Capítulo 9).
- **Sinais**: ao parar um container, o runtime envia `SIGTERM` (encerramento gracioso), aguarda um período (grace period) e então envia `SIGKILL`. Aplicações bem-comportadas tratam o `SIGTERM` para fechar conexões antes de morrer — isso é a base do deploy sem downtime.

**Laboratório sugerido 1.2** *(requer Docker ou nerdctl instalado)*

```bash
# 1. Rode um container e observe seu ciclo de vida
podman run --name teste -d nginx:1.27
podman ps                          # estado Running
podman inspect teste --format '{{.State.Status}}'

# 2. Explore as camadas da imagem
podman history nginx:1.27

# 3. Prove que a camada de escrita é efêmera
podman exec teste sh -c 'echo oi > /tmp/arquivo && cat /tmp/arquivo'
podman rm -f teste
podman run --name teste -d nginx:1.27
podman exec teste cat /tmp/arquivo   # o arquivo não existe mais

# 4. Observe o encerramento gracioso
podman stop teste                    # envia SIGTERM, depois SIGKILL
podman inspect teste --format '{{.State.ExitCode}}'
podman rm teste
```

---

## 1.3 Arquitetura do Kubernetes

Um **cluster** Kubernetes é um conjunto de máquinas (físicas ou virtuais), chamadas **nós**, divididas em dois papéis:

- **Control plane**: o "cérebro" — decide o que deve rodar e onde, e mantém o estado do cluster.
- **Nós de trabalho (workers)**: o "músculo" — executam de fato os containers das aplicações.

```
                        CONTROL PLANE
        ┌──────────────────────────────────────────┐
        │  ┌──────────────┐      ┌──────────────┐  │
kubectl │  │ kube-apiserver│◀───▶│     etcd     │  │
──────────▶│  (porta de    │      │ (banco de    │  │
        │  │   entrada)    │      │   estado)    │  │
        │  └──────┬───────┘      └──────────────┘  │
        │         │ watch/update                    │
        │  ┌──────┴───────┐   ┌──────────────────┐ │
        │  │  scheduler   │   │controller-manager│ │
        │  └──────────────┘   └──────────────────┘ │
        └───────────────────┬──────────────────────┘
                            │ (API)
        ┌───────────────────┼──────────────────────┐
        │       ┌───────────┴──────────┐           │
        │  ┌────┴─────┐  ┌─────┴────┐  ┌────┴─────┐│
        │  │  Nó 1    │  │  Nó 2    │  │  Nó 3    ││
        │  │ kubelet  │  │ kubelet  │  │ kubelet  ││
        │  │kube-proxy│  │kube-proxy│  │kube-proxy││
        │  │containerd│  │containerd│  │containerd││
        │  │ [Pods]   │  │ [Pods]   │  │ [Pods]   ││
        │  └──────────┘  └──────────┘  └──────────┘│
        │              NÓS DE TRABALHO             │
        └──────────────────────────────────────────┘
```

### 1.3.1 Control plane: kube-apiserver, etcd, scheduler, controller-manager

**kube-apiserver — a porta de entrada única**
Tudo no Kubernetes passa pelo API server: comandos do `kubectl`, dashboards, CI/CD e até os demais componentes do control plane. Ele:

- Expõe uma API REST para todos os recursos (Pods, Services, Deployments...).
- **Autentica** quem chama, **autoriza** (RBAC, Capítulo 8) e **valida/modifica** requisições (admission controllers).
- É o **único** componente que fala com o etcd. Ninguém mais lê ou escreve no banco diretamente.
- É *stateless*: pode (e deve, em produção) ter múltiplas réplicas atrás de um load balancer.

**etcd — a fonte da verdade**
Banco de dados chave-valor distribuído que guarda **todo o estado do cluster**: cada objeto que você cria vira um registro no etcd.

- Usa o algoritmo de consenso **Raft** — por isso clusters HA usam número ímpar de membros (3 ou 5): com 3 membros, o cluster tolera a perda de 1 e ainda mantém quórum (maioria).
- Suporta *watch*: clientes são notificados em tempo real quando um valor muda — é isso que permite ao Kubernetes reagir a mudanças instantaneamente, sem polling.
- **Perdeu o etcd sem backup, perdeu o cluster.** Backup do etcd é tema do Capítulo 6.

**kube-scheduler — quem decide "onde"**
Observa Pods recém-criados que ainda não têm nó atribuído e escolhe o melhor nó para cada um, em duas fases:

1. **Filtragem**: elimina nós inviáveis (sem CPU/memória suficiente, com taints não tolerados, que não atendem às regras de afinidade — Capítulo 7).
2. **Pontuação**: ranqueia os nós restantes (distribuição de carga, espalhamento de réplicas) e escolhe o vencedor.

Importante: o scheduler apenas **escreve a decisão** no objeto Pod (campo `nodeName`) via API. Quem executa é o kubelet do nó escolhido.

**kube-controller-manager — quem garante o "estado desejado"**
Executa dezenas de **controllers**, cada um responsável por um tipo de recurso: o *Deployment controller*, o *ReplicaSet controller* (garante N réplicas), o *Node controller* (detecta nós mortos), o *Job controller*, entre outros. Todos seguem o mesmo padrão — o loop de reconciliação, detalhado na seção 1.3.3.

> Em clusters na nuvem existe ainda o **cloud-controller-manager**, que integra o cluster ao provedor (cria load balancers, discos, rotas de rede).

### 1.3.2 Nós de trabalho: kubelet, kube-proxy, container runtime

Cada nó de trabalho executa três componentes:

**kubelet — o agente do nó**
- Registra o nó no cluster e reporta periodicamente sua saúde e capacidade.
- Observa, via API server, quais Pods foram atribuídos ao seu nó e instrui o container runtime (pela interface **CRI**) a criar/destruir os containers correspondentes.
- Executa as **probes** de liveness/readiness/startup (Capítulo 3) e reinicia containers que falham.
- Detalhe de arquitetura: o kubelet é o único componente do Kubernetes que roda como serviço do sistema operacional (systemd), e não como container gerenciado — afinal, alguém precisa existir *antes* dos containers para criá-los.

**kube-proxy — a rede dos Services**
- Implementa, em cada nó, o encaminhamento de tráfego dos **Services** (Capítulo 4): quando algo acessa o IP virtual de um Service, o kube-proxy garante que o pacote chegue a um dos Pods de destino.
- Tradicionalmente usa regras de **iptables** ou **IPVS**; alguns CNIs modernos (como o Cilium, via eBPF) o substituem completamente.

**Container runtime**
- O containerd (ou CRI-O) que estudamos na seção 1.2: recebe ordens do kubelet via CRI e materializa os containers.

> **Curiosidade que consolida o modelo**: os próprios componentes do control plane (API server, scheduler, controller-manager, etcd) normalmente rodam como Pods nos nós de control plane, criados pelo kubelet a partir de *static pod manifests*. O Kubernetes se gerencia com os próprios mecanismos. Você verá isso de perto ao usar o kubeadm no Capítulo 6.

### 1.3.3 O modelo declarativo e o loop de reconciliação

Esta é a ideia mais importante do curso. Se você entender esta seção, todo o resto do Kubernetes fará sentido.

**Imperativo vs. declarativo**

- **Imperativo**: você dá ordens passo a passo. "Crie 3 containers da imagem X no servidor Y." Se um morrer, *você* precisa perceber e agir.
- **Declarativo**: você descreve o **estado desejado**. "Devem existir 3 réplicas da imagem X." O sistema descobre sozinho *como* chegar lá — e *como permanecer lá*.

No Kubernetes, o estado desejado é expresso em manifestos (YAML) e armazenado no etcd. Exemplo mínimo:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-pedidos
spec:
  replicas: 3          # ← estado desejado: 3 réplicas
  selector:
    matchLabels:
      app: api-pedidos
  template:
    metadata:
      labels:
        app: api-pedidos
    spec:
      containers:
      - name: api
        image: registry.exemplo.com/loja/api-pedidos:2.4.1
```

**O loop de reconciliação (reconciliation loop)**

Cada controller executa, para sempre, o mesmo ciclo:

```
        ┌──────────────────────────────────┐
        │  1. OBSERVAR o estado atual      │
        │     (via API server / watch)     │
        └──────────────┬───────────────────┘
                       ▼
        ┌──────────────────────────────────┐
        │  2. COMPARAR com o estado        │
        │     desejado (spec no etcd)      │
        └──────────────┬───────────────────┘
                       ▼
        ┌──────────────────────────────────┐
        │  3. AGIR para eliminar a         │
        │     diferença (criar/apagar/     │
        │     atualizar recursos)          │
        └──────────────┬───────────────────┘
                       └────────▶ volta ao passo 1
```

**Acompanhe uma falha na prática.** Suponha o Deployment acima com 3 réplicas rodando, e o Nó 2 (que hospedava uma delas) sofre uma queda de energia:

1. O kubelet do Nó 2 para de enviar heartbeats; após o tempo limite, o *Node controller* marca o nó como `NotReady`.
2. Os Pods daquele nó são marcados para remoção; o *ReplicaSet controller*, ao comparar, encontra: **desejado = 3, atual = 2**.
3. Ele cria um novo Pod (ainda sem nó) para fechar a conta.
4. O *scheduler* vê o Pod pendente, filtra e pontua os nós saudáveis, e o atribui ao Nó 3.
5. O *kubelet* do Nó 3 vê o novo Pod atribuído a ele e manda o containerd baixar a imagem e iniciar o container.
6. Estado atual = estado desejado. O sistema convergiu — **sem nenhuma intervenção humana**.

Repare em dois detalhes elegantes dessa história:

- **Ninguém orquestrou a recuperação de ponta a ponta.** Cada componente é simples, observa a API e cuida apenas da sua parte. A resiliência **emerge** da colaboração entre loops independentes. Esse desenho é chamado de *coreografia* (em oposição a um maestro central) e é o que torna o Kubernetes robusto e extensível.
- **O mesmo mecanismo serve para tudo**: recuperar de falhas, escalar (mudar `replicas` de 3 para 30 é só editar o estado desejado), atualizar versões (mudar a tag da imagem dispara o rolling update) e até estender o Kubernetes — os **Operators** do Capítulo 10 são exatamente isso: controllers customizados rodando o mesmo loop sobre recursos que você define.

**Exercício de fixação 1.3**
1. Por que o etcd de um cluster HA tem 3 ou 5 membros, e não 2 ou 4?
2. Qual componente decide em qual nó um Pod vai rodar? E qual componente efetivamente inicia o container?
3. Você editou um Deployment mudando `replicas: 3` para `replicas: 5`. Descreva, componente por componente, o que acontece até os 2 novos Pods estarem rodando.
4. Explique com suas palavras a diferença entre "dar um comando para criar 3 containers" e "declarar que devem existir 3 réplicas".

---

## Resumo do capítulo

- Containers isolam processos usando **namespaces e cgroups** do kernel, com fração do overhead das VMs; o Docker popularizou o formato em 2013 e o **padrão OCI** garantiu a interoperabilidade do ecossistema.
- Orquestração resolve os problemas que aparecem **em escala**: agendamento, self-healing, escala automática, deploys sem downtime e descoberta de serviços.
- O Kubernetes fala com o runtime via **CRI**; hoje o padrão é o **containerd**. Imagens Docker continuam funcionando normalmente, pois são imagens OCI.
- O **control plane** (API server, etcd, scheduler, controller-manager) decide; os **nós de trabalho** (kubelet, kube-proxy, runtime) executam. O API server é a porta única; o etcd é a fonte da verdade.
- Tudo no Kubernetes é **declarativo**: você define o estado desejado e **loops de reconciliação** trabalham continuamente para tornar o estado real igual ao desejado.

**Ponte para o Capítulo 2**: agora que você sabe *o que* é cada peça, vamos colocar a mão na massa — instalar um cluster standalone na sua máquina e ver todos esses componentes rodando de verdade.
