# Capítulo 4 — Rede e exposição de serviços

> **Objetivos de aprendizagem**
> Ao final deste capítulo, você será capaz de:
> 1. Enunciar as regras do modelo de rede do Kubernetes e explicar por que "um IP por Pod" simplifica tudo.
> 2. Explicar o que é a CNI e comparar Calico, Flannel e Cilium.
> 3. Criar e diferenciar Services ClusterIP, NodePort e LoadBalancer, entendendo Endpoints e kube-proxy.
> 4. Usar o DNS interno (CoreDNS) para service discovery entre aplicações.
> 5. Instalar um Ingress Controller e configurar roteamento por host e por path.
> 6. Habilitar TLS em um Ingress com certificados.

---

## 4.1 Modelo de rede do Kubernetes

### 4.1.1 IP por Pod e comunicação entre Pods

O Kubernetes impõe um modelo de rede deliberadamente simples, com três regras:

1. **Todo Pod tem seu próprio IP**, único no cluster.
2. **Todo Pod alcança todo Pod diretamente**, em qualquer nó, **sem NAT**.
3. **Os agentes de um nó** (kubelet, por exemplo) alcançam os Pods daquele nó.

Compare com o mundo "Docker puro": lá, containers compartilham o IP do host e você publica portas (`-p 8080:80`), gerenciando um mapa de portas por servidor — quem nunca sofreu com "porta 8080 já está em uso"? No modelo Kubernetes, esse problema **não existe**: como cada Pod tem seu IP, duas instâncias do mesmo app no mesmo nó podem ambas escutar na porta 80, cada uma no seu IP.

Consequência conceitual importante: **o Pod se comporta como uma pequena VM na rede**. Aplicações não precisam saber que estão em containers; portas não colidem; e o IP que um Pod vê como origem de uma conexão é o IP real do Pod remoto.

**Os espaços de endereçamento do cluster** (você os verá na prática ao configurar o kubeadm no Capítulo 6):

- **Pod CIDR** (ex.: `10.244.0.0/16`): a faixa de onde saem os IPs dos Pods; cada nó recebe uma sub-faixa (ex.: nó 1 = `10.244.1.0/24`).
- **Service CIDR** (ex.: `10.96.0.0/12`): faixa dos IPs virtuais de Services (seção 4.2).
- **Rede dos nós**: a rede "física" das máquinas.

**Mas lembre-se do Capítulo 3: Pods são efêmeros.** O IP de um Pod muda a cada recriação. Portanto, a regra de ouro da rede no Kubernetes: **nunca aponte para IPs de Pods** — aponte para Services (seção 4.2), que fornecem o endereço estável. O IP-por-Pod é a fundação; o Service é a abstração que você realmente usa.

```bash
# Veja com seus olhos:
kubectl create deploy web --image=nginx:1.27 --replicas=2
kubectl get pods -o wide            # note os IPs dos Pods
kubectl run cliente --rm -it --image=busybox:1.36 -- sh
# dentro do container cliente:
wget -qO- http://<IP-de-um-pod>     # HTML do nginx: Pod alcança Pod, sem NAT
exit
```

### 4.1.2 CNI: o que é e principais plugins (Calico, Flannel, Cilium)

O Kubernetes **define** as regras da seção anterior, mas **não as implementa**. Quem implementa é um plugin de rede, seguindo a especificação **CNI (Container Network Interface)** — mais um padrão aberto, na mesma filosofia da CRI (Capítulo 1): o kubelet chama o plugin CNI sempre que um Pod nasce ("dê uma interface e um IP a este Pod") ou morre.

É por isso que, no Capítulo 6, um cluster recém-criado com kubeadm fica com os nós `NotReady` até você **instalar um CNI** — sem ele, Pods não ganham rede. (Minikube e k3s já trazem um embutido, por isso você ainda não precisou pensar nisso.)

Como o tráfego atravessa nós varia por plugin — os dois mecanismos comuns:

- **Overlay (encapsulamento)**: pacotes entre Pods viajam encapsulados (VXLAN) dentro de pacotes entre nós. Funciona em qualquer rede subjacente; custo: pequeno overhead.
- **Rotas nativas (L3/BGP)**: os nós trocam rotas ("a faixa 10.244.1.0/24 está comigo") e os pacotes fluem sem encapsulamento. Mais eficiente; exige uma rede que permita isso.

**Os três plugins mais relevantes:**

| | **Flannel** | **Calico** | **Cilium** |
|---|---|---|---|
| Foco | Simplicidade | Rede + segurança | Rede + segurança + observabilidade |
| Mecanismo típico | Overlay VXLAN | BGP/rotas (ou VXLAN) | eBPF (com ou sem overlay) |
| NetworkPolicy | **Não** suporta | Sim (e políticas estendidas) | Sim (até L7: HTTP, gRPC) |
| Desempenho | Bom | Muito bom | Excelente (dispensa kube-proxy) |
| Complexidade | Mínima | Média | Média/alta |
| Quando escolher | Labs, clusters simples | Produção "clássica", on-prem com BGP | Produção moderna, requisitos de observabilidade/segurança L7 |

- **Flannel**: o minimalista — faz as três regras funcionarem e nada mais. Perfeito para aprender; limitado para produção séria (sem NetworkPolicies, que usaremos no Capítulo 8).
- **Calico**: o veterano de produção — rede eficiente e o suporte de referência a NetworkPolicies. Será nossa escolha no cluster do Capítulo 6.
- **Cilium**: a geração **eBPF** — programa o kernel diretamente, substitui o kube-proxy, enxerga tráfego em camada 7 e traz o Hubble para observabilidade de rede. É a tendência da indústria (é o CNI padrão do GKE Dataplane V2 e de várias distribuições modernas).

> **eBPF em uma frase**: tecnologia do kernel Linux que permite executar programas seguros dentro do kernel, sem módulos — o que deixa o processamento de rede mais rápido e mais observável do que cadeias de iptables.

**Exercício de fixação 4.1**
1. Enuncie as três regras do modelo de rede do Kubernetes. Qual problema do "Docker puro" a regra do IP-por-Pod elimina?
2. Por que apontar uma aplicação para o IP de um Pod é um erro, mesmo esse IP sendo alcançável?
3. O que acontece com um cluster kubeadm sem CNI instalado, e por quê?
4. Sua empresa exigirá isolamento de tráfego entre namespaces (NetworkPolicies). Entre Flannel, Calico e Cilium, quais atendem? Qual critério o desempate?

---

## 4.2 Services

### 4.2.1 ClusterIP, NodePort, LoadBalancer

O **Service** resolve o problema do IP efêmero: é um **endereço virtual estável** (IP + nome DNS) na frente de um conjunto de Pods, com balanceamento de carga entre eles. E como ele encontra os Pods? Do único jeito que o Kubernetes conhece: **por labels** (Capítulo 3).

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  type: ClusterIP              # o padrão
  selector:
    app: web                   # Pods com esta label recebem o tráfego
  ports:
  - port: 80                   # porta do Service
    targetPort: 80             # porta do container
```

**Por baixo: Endpoints.** Um controller observa continuamente quais Pods casam com o selector **e estão Ready** (eis a readiness probe do Capítulo 3 fechando o circuito!) e mantém a lista de IPs em objetos **EndpointSlice**. O **kube-proxy** (Capítulo 1) materializa em cada nó as regras (iptables/IPVS) que traduzem "IP do Service" → "um dos IPs da lista".

```bash
kubectl get svc web                        # o IP estável (ClusterIP)
kubectl get endpointslices -l kubernetes.io/service-name=web   # os IPs dos Pods por trás
kubectl delete pod -l app=web --wait=false && kubectl get endpointslices -w
# os endpoints trocam sozinhos — o IP do Service, nunca
```

**Os três tipos formam camadas — cada um inclui o anterior:**

**ClusterIP — acesso interno (o padrão)**
IP virtual alcançável **apenas de dentro do cluster**. É o tipo para 90% dos casos: comunicação serviço-a-serviço (API → banco, frontend → API).

**NodePort — abre uma porta em cada nó**
Além do ClusterIP, reserva uma porta (faixa padrão **30000–32767**) em **todos os nós**; tráfego chegando em `IP-de-qualquer-nó:porta` é encaminhado ao Service (mesmo que o Pod esteja em outro nó).

```yaml
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080        # opcional; sem ele, o K8s sorteia na faixa
```

Simples e sem dependências — mas portas altas e feias, um porta por serviço e o cliente precisa conhecer IPs de nós (que também mudam). Útil para labs e como bloco de construção; raramente exposto diretamente a usuários finais.

**LoadBalancer — o IP externo "de verdade"**
Além do NodePort, pede à infraestrutura um **balanceador externo** com IP público apontando para os nós. Em nuvem (EKS/GKE/AKS), o cloud-controller-manager (Capítulo 1) provisiona o balanceador automaticamente; **em bare metal não existe mágica** — você precisa de um provedor como o **MetalLB** (voltaremos a isso no Capítulo 6). No Minikube, `minikube tunnel` simula o comportamento.

```
                     [ LoadBalancer: IP externo ]      (nuvem/MetalLB)
                                 │
                     [ NodePort: nó1:30080, nó2:30080, ... ]
                                 │
                     [ ClusterIP: 10.96.44.7:80 ]
                                 │        (kube-proxy + EndpointSlices)
                    ┌────────────┼────────────┐
                 [Pod A]      [Pod B]      [Pod C]
```

> **Custo à vista**: um LoadBalancer **por serviço** significa um balanceador (pago, em nuvem) por serviço. Com dezenas de serviços HTTP, isso não escala financeiramente — é exatamente o problema que o **Ingress** (seção 4.3) resolve: *um* ponto de entrada para *muitos* serviços.

> **Menção honrosa**: `type: ExternalName` (um alias DNS para um serviço externo) e **headless services** (`clusterIP: None`) — sem IP virtual, o DNS devolve os IPs dos Pods diretamente; é o par natural do StatefulSet e reaparecerá no Capítulo 5.

### 4.2.2 DNS interno (CoreDNS) e service discovery

Decorar ClusterIPs seria tão ruim quanto decorar IPs de Pods. Por isso todo cluster roda o **CoreDNS** (você o viu no `kube-system` desde o Capítulo 2): cada Service ganha automaticamente um **nome DNS**:

```
<service>.<namespace>.svc.cluster.local
   web    .  loja-dev .svc.cluster.local
```

E o kubelet configura o `/etc/resolv.conf` de cada container para usar o CoreDNS com uma lista de sufixos de busca. Resultado prático:

- Mesmo namespace: basta **`web`**.
- Outro namespace: **`web.loja-prod`** (ou o nome completo).

**Isto é service discovery no Kubernetes**: nenhuma biblioteca, nenhum registro externo — a aplicação simplesmente usa nomes:

```yaml
env:
- name: DATABASE_URL
  value: "postgres://usuario:senha@db:5432/loja"   # "db" é um Service!
```

**Laboratório de descoberta:**

```bash
kubectl create deploy web --image=nginx:1.27 --replicas=2
kubectl expose deploy web --port=80                  # cria o Service ClusterIP
kubectl run cliente --rm -it --image=busybox:1.36 -- sh
# dentro:
nslookup web                                 # resolve para o ClusterIP
cat /etc/resolv.conf                         # os sufixos de busca em ação
wget -qO- http://web                         # nome curto, mesmo namespace
wget -qO- http://web.default.svc.cluster.local   # nome completo
exit
```

> **Dica de troubleshooting** (semente para o Capítulo 9): boa parte dos "problemas de rede" em Kubernetes são, na verdade, DNS ou selectors errados. O teste em três passos: (1) `kubectl get endpointslices ...` — o Service tem endpoints? Se está vazio, o selector não casa com nenhum Pod **Ready**; (2) `nslookup <service>` de dentro de um Pod — o nome resolve?; (3) acesse o ClusterIP diretamente — se funciona por IP mas não por nome, o problema é DNS.

**Exercício de fixação 4.2**
1. Um Service tem selector `app: api`, mas `kubectl get endpointslices` mostra lista vazia. Cite as duas causas mais prováveis (dica: uma envolve o Capítulo 3).
2. Por que um Pod que ainda não passou na readiness probe não recebe tráfego do Service? Que objeto intermediário materializa isso?
3. Do namespace `frontend`, qual o menor nome DNS para alcançar o Service `pedidos` no namespace `backend`?
4. Sua aplicação tem 30 microsserviços HTTP que precisam ser acessíveis externamente. Por que 30 Services LoadBalancer é uma má ideia, e qual é a alternativa?

---

## 4.3 Ingress

### 4.3.1 Ingress Controllers (NGINX, Traefik)

O **Ingress** é o roteador HTTP/HTTPS do cluster: **um único ponto de entrada** que distribui requisições para vários Services com base em **host** e **path** — camada 7, onde LoadBalancer/NodePort operam na camada 4.

A peça mais importante para entender: **o recurso Ingress é só a declaração das regras**. Quem as executa é um **Ingress Controller** — um proxy reverso (rodando como Pods no cluster, tipicamente atrás de um único Service LoadBalancer) que observa os objetos Ingress via API e se reconfigura dinamicamente. Sem controller instalado, criar Ingress **não faz nada**. É o mesmo padrão declaração/executor que você já conhece: assim como o Ingress precisa de um controller, o CNI implementa o modelo de rede — o Kubernetes define interfaces, o ecossistema implementa.

**Os controllers mais comuns:**

- **Ingress-NGINX**: o mais difundido, mantido pela comunidade Kubernetes; baseia-se no NGINX e é configurável por annotations (você viu um exemplo no Capítulo 3). É a escolha "padrão de mercado" e a do nosso curso.
- **Traefik**: proxy moderno com descoberta dinâmica e dashboard próprio; é o controller **embutido no k3s** — se você seguiu o caminho k3s no Capítulo 2, já tem um.
- Outros que você encontrará por aí: HAProxy Ingress, Contour (Envoy), e os controllers gerenciados das nuvens (ALB na AWS, GCLB no GKE).

> **Nota de futuro**: a **Gateway API** é a evolução oficial do Ingress (recursos `Gateway`, `HTTPRoute`), mais expressiva e padronizada. O Ingress continua onipresente e é o que você deve dominar primeiro; apenas saiba que o sucessor já existe.

**Instalação no Minikube (um comando, graças aos addons do Capítulo 2):**

```bash
minikube addons enable ingress
kubectl get pods -n ingress-nginx        # o controller rodando
```

(Em clusters kubeadm, a instalação é por manifesto/Helm — faremos no Capítulo 6.)

### 4.3.2 Roteamento por host e path

Prepare dois serviços de exemplo:

```bash
kubectl create deploy loja --image=nginxdemos/hello:plain-text --replicas=2
kubectl create deploy blog --image=nginxdemos/hello:plain-text --replicas=2
kubectl expose deploy loja --port=80
kubectl expose deploy blog --port=80
```

**Roteamento por host** (virtual hosts — vários domínios, um IP):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sites
spec:
  ingressClassName: nginx            # qual controller deve honrar este Ingress
  rules:
  - host: loja.exemplo.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: loja
            port: { number: 80 }
  - host: blog.exemplo.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: blog
            port: { number: 80 }
```

**Roteamento por path** (um domínio, vários serviços):

```yaml
  rules:
  - host: app.exemplo.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service: { name: api, port: { number: 8080 } }
      - path: /
        pathType: Prefix
        backend:
          service: { name: frontend, port: { number: 80 } }
```

Pontos de atenção:

- **`ingressClassName`** liga o Ingress ao controller certo (um cluster pode ter vários).
- **`pathType`**: `Prefix` (casa `/api`, `/api/v1`...) ou `Exact` (só o caminho exato). Regras mais específicas vencem — por isso `/api` pode vir junto de `/` no exemplo.
- Alguns apps precisam de reescrita de caminho (receber `/` embora publicados sob `/api`); no Ingress-NGINX isso se faz com a annotation `nginx.ingress.kubernetes.io/rewrite-target` — reconheça-a quando vir.
- O backend do Ingress é sempre um **Service** (tipicamente ClusterIP) — o Ingress não fala com Pods diretamente. A cadeia completa: **DNS público → LoadBalancer → Ingress Controller → regra (host/path) → Service → EndpointSlice → Pod**.

**Testando sem possuir os domínios** — duas opções de laboratório:

```bash
# A) Forjar o Host header:
curl -H "Host: loja.exemplo.com" http://$(minikube ip)/

# B) Mapear no /etc/hosts da sua máquina:
echo "$(minikube ip) loja.exemplo.com blog.exemplo.com" | sudo tee -a /etc/hosts
curl http://loja.exemplo.com/
```

(No driver docker do Minikube em macOS/Windows, use `minikube tunnel` e aponte os hosts para `127.0.0.1`.)

### 4.3.3 TLS básico no Ingress

HTTPS no Ingress segue um desenho eficiente: o **controller termina o TLS** (descriptografa na borda) e encaminha o tráfego internamente. Certificado e chave vivem em um **Secret do tipo `kubernetes.io/tls`** — nosso primeiro contato com Secrets, que o Capítulo 5 aprofunda.

**1. Gere um certificado de laboratório (autoassinado):**

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=loja.exemplo.com" \
  -addext "subjectAltName=DNS:loja.exemplo.com"
```

**2. Crie o Secret:**

```bash
kubectl create secret tls loja-tls --cert=tls.crt --key=tls.key
```

**3. Referencie no Ingress:**

```yaml
spec:
  ingressClassName: nginx
  tls:
  - hosts: [loja.exemplo.com]
    secretName: loja-tls
  rules:
  - host: loja.exemplo.com
    ...
```

**4. Teste:**

```bash
curl -k https://loja.exemplo.com/      # -k aceita o certificado autoassinado
curl -kv https://loja.exemplo.com/ 2>&1 | grep -E 'subject|issuer'
```

O Ingress-NGINX também passa a **redirecionar HTTP → HTTPS automaticamente** quando um bloco `tls` existe (comportamento configurável por annotation).

> **Do laboratório para a produção**: ninguém gerencia certificados na mão. O padrão da indústria é o **cert-manager**: ele observa os Ingress, solicita certificados gratuitos à **Let's Encrypt** (protocolo ACME), grava-os nos Secrets e **renova sozinho** antes de expirarem. O cert-manager é um *Operator* — mais um motivo para a ansiedade positiva até o Capítulo 10, onde o instalaremos.

**Exercício de fixação 4.3**
1. Você criou um Ingress e nada aconteceu — `curl` não conecta. Qual é a primeira hipótese a verificar, e por quê?
2. Explique a diferença entre o recurso Ingress e o Ingress Controller usando a analogia declaração/executor do curso.
3. Monte (em YAML) as regras para: `api.acme.com/v1` → Service `api-v1:8080`; `api.acme.com/` → Service `portal:80`. Que `pathType` você usa e por que a ordem/especificidade importa?
4. No desenho "TLS terminado no Ingress", o tráfego entre o controller e os Pods é criptografado? Que implicação isso tem e que tipo de solução (mencionada no Capítulo 3, seção de sidecars) endereça isso?

---

## Laboratório consolidado do capítulo

A cadeia completa, de dentro para fora (~35 min):

```bash
minikube start
minikube addons enable ingress
kubectl create namespace lab4
kubectl config set-context --current --namespace=lab4

# 1. Fundação: Pods e seus IPs efêmeros
kubectl create deploy loja --image=nginxdemos/hello:plain-text --replicas=3
kubectl get pods -o wide

# 2. Estabilidade: Service ClusterIP + endpoints + DNS
kubectl expose deploy loja --port=80
kubectl get svc,endpointslices
kubectl run cliente --rm -it --image=busybox:1.36 -- \
  sh -c 'nslookup loja && wget -qO- http://loja | head -3'

# 3. Prova do balanceamento (o hello devolve o nome do Pod que respondeu)
kubectl run cliente --rm -it --image=busybox:1.36 -- \
  sh -c 'for i in 1 2 3 4 5 6; do wget -qO- http://loja | grep -i name; done'

# 4. Exposição L4: NodePort
kubectl expose deploy loja --port=80 --type=NodePort --name=loja-np
kubectl get svc loja-np                      # anote a porta 3xxxx
curl http://$(minikube ip):<porta-3xxxx>/

# 5. Exposição L7: Ingress com host + TLS
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt \
  -subj "/CN=loja.exemplo.com" -addext "subjectAltName=DNS:loja.exemplo.com"
kubectl create secret tls loja-tls --cert=tls.crt --key=tls.key
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: loja
spec:
  ingressClassName: nginx
  tls:
  - hosts: [loja.exemplo.com]
    secretName: loja-tls
  rules:
  - host: loja.exemplo.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: loja
            port: { number: 80 }
EOF
curl -k --resolve loja.exemplo.com:443:$(minikube ip) https://loja.exemplo.com/

# 6. Self-healing da rede: mate Pods e veja os endpoints se atualizarem
kubectl delete pod -l app=loja --wait=false
kubectl get endpointslices -w                # Ctrl+C quando estabilizar
curl -k --resolve loja.exemplo.com:443:$(minikube ip) https://loja.exemplo.com/  # segue no ar

# 7. Limpeza
kubectl delete namespace lab4
kubectl config set-context --current --namespace=default
```

---

## Resumo do capítulo

- O modelo de rede: **um IP por Pod, todos alcançam todos, sem NAT** — Pods se comportam como pequenas VMs, e colisão de portas deixa de existir. Quem implementa é o **CNI**: Flannel (simples, sem NetworkPolicy), Calico (produção clássica, BGP), Cilium (eBPF, L7, substitui o kube-proxy).
- IPs de Pods são efêmeos; o **Service** dá o endereço estável e balanceia entre os Pods **Ready** (via EndpointSlices + kube-proxy). Camadas: **ClusterIP** (interno) ⊂ **NodePort** (porta 30000–32767 em cada nó) ⊂ **LoadBalancer** (IP externo — nuvem ou MetalLB).
- **CoreDNS** dá nome a cada Service (`svc.ns.svc.cluster.local`); service discovery vira simplesmente "usar nomes". Service sem endpoints = selector errado ou Pods não-Ready.
- O **Ingress** é o roteador L7: um ponto de entrada, muitas regras de **host/path** para Services internos — mas só funciona com um **Ingress Controller** instalado (NGINX é o padrão de mercado; Traefik vem no k3s).
- **TLS** termina no controller, com certificado em um Secret `kubernetes.io/tls`; em produção, o **cert-manager** automatiza emissão e renovação via Let's Encrypt.

**Ponte para o Capítulo 5**: suas aplicações já se encontram e recebem tráfego do mundo — mas ainda carregam configurações fixas na imagem, senhas expostas e nenhum lugar para guardar dados que sobrevivam a um restart. Configuração, Secrets e armazenamento persistente são o próximo passo.
