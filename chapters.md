# Capítulo 1 — Fundamentos e contexto
## Por que Kubernetes existe
### Do bare metal às VMs e aos containers
### Problemas que a orquestração resolve (escala, resiliência, deploy)
## Revisão rápida de containers
### Docker / containerd / CRI-O e o padrão OCI
### Imagens, registries e o ciclo de vida de um container
## Arquitetura do Kubernetes
### Control plane: kube-apiserver, etcd, scheduler, controller-manager
### Nós de trabalho: kubelet, kube-proxy, container runtime
### O modelo declarativo e o loop de reconciliação

# Capítulo 2 — Instalação standalone (nó único)
## Opções para ambiente local
### Minikube
### Kind (Kubernetes in Docker)
### k3s / MicroK8s
### Comparativo: quando usar cada um
## Instalação passo a passo (laboratório)
### Pré-requisitos de máquina (CPU, RAM, virtualização)
### Instalando o kubectl
### Subindo o primeiro cluster de nó único
### Verificando a saúde do cluster (kubectl get nodes, cluster-info)
## Primeiros comandos com kubectl
### Contextos e kubeconfig
### get, describe, logs, exec
### Modo imperativo vs. declarativo (YAML)

# Capítulo 3 — Objetos fundamentais
## Pods
### Anatomia de um Pod e ciclo de vida
### Multi-container Pods e sidecars
### Probes: liveness, readiness, startup
## Controladores de workload
### ReplicaSet
### Deployment (rolling update e rollback)
### DaemonSet, StatefulSet e Job/CronJob (visão geral)
## Namespaces
### Organização lógica de recursos
### Labels, selectors e annotations

# Capítulo 4 — Rede e exposição de serviços
## Modelo de rede do Kubernetes
### IP por Pod e comunicação entre Pods
### CNI: o que é e principais plugins (Calico, Flannel, Cilium)
## Services
### ClusterIP, NodePort, LoadBalancer
### DNS interno (CoreDNS) e service discovery
## Ingress
### Ingress Controllers (NGINX, Traefik)
### Roteamento por host e path
### TLS básico no Ingress

# Capítulo 5 — Configuração e armazenamento
## Configuração de aplicações
### ConfigMaps
### Secrets (e suas limitações de segurança)
### Variáveis de ambiente vs. volumes montados
## Armazenamento persistente
### Volumes efêmeros vs. persistentes
### PersistentVolume e PersistentVolumeClaim
### StorageClasses e provisionamento dinâmico
## StatefulSets na prática
### Rodando um banco de dados (ex.: PostgreSQL) no cluster
### Headless services e identidade estável

# Capítulo 6 — Montando um cluster multi-nó (3+ nós)
## Planejamento do cluster
### Topologia: 1 control plane + 2 workers vs. HA com 3 control planes
### Requisitos de rede, hostname, swap e firewall
### Escolha do runtime (containerd) e do CNI
## Bootstrap com kubeadm (laboratório principal)
### Preparação dos nós (kernel modules, sysctl, containerd)
### kubeadm init no control plane
### Instalando o plugin de rede (CNI)
### kubeadm join dos workers
### Validando o cluster com workloads de teste
## Alternativas de instalação
### k3s multi-nó
### Kubespray (visão geral)
### Clusters gerenciados: EKS, GKE, AKS (comparativo)
## Operações essenciais do cluster
### Cordon, drain e manutenção de nós
### Upgrade de versão com kubeadm
### Backup e restore do etcd
### Adicionando e removendo nós

# Capítulo 7 — Scheduling, escalabilidade e resiliência
## Controle de alocação
### Requests e limits de recursos
### Taints, tolerations e nodeSelector
### Affinity e anti-affinity
## Escalabilidade
### Horizontal Pod Autoscaler (HPA)
### Vertical Pod Autoscaler (visão geral)
### Cluster Autoscaler (conceito)
## Resiliência
### PodDisruptionBudgets
### Estratégias de deploy: rolling, blue-green, canary

# Capítulo 8 — Segurança
## Autenticação e autorização
### ServiceAccounts
### RBAC: Roles, ClusterRoles e bindings
## Segurança de workloads
### SecurityContext e Pod Security Standards
### NetworkPolicies (isolamento de tráfego)
## Boas práticas
### Gestão de secrets (Sealed Secrets, external secrets — visão geral)
### Scan de imagens e supply chain

# Capítulo 9 — Observabilidade e troubleshooting
## Logs e métricas
### kubectl logs e metrics-server
### Stack Prometheus + Grafana (instalação básica)
## Troubleshooting sistemático
### Diagnóstico de Pods (CrashLoopBackOff, ImagePullBackOff, OOMKilled)
### Diagnóstico de rede e DNS
### Diagnóstico de nós e do control plane
## Eventos e auditoria
### kubectl events e ferramentas auxiliares (k9s, stern)

# Capítulo 10 — Estendendo o Kubernetes: CRDs e Operators
## Extensibilidade da API
### Custom Resource Definitions (CRDs)
### Criando e consultando um Custom Resource com kubectl
### Validação de schema (OpenAPI) e versionamento de CRDs
## O padrão Operator
### O que é um Operator: CRD + controller + conhecimento operacional
### O loop de reconciliação aplicado a recursos customizados
### Capability levels: de instalação básica a auto-pilot
## Usando Operators prontos (laboratório)
### OperatorHub e formas de instalação
### Exemplos práticos: cert-manager, Prometheus Operator
### Operators de banco de dados (ex.: CloudNativePG para PostgreSQL)
### Ciclo de vida: instalação, upgrade e remoção segura
## Construindo seu próprio Operator (visão geral)
### Kubebuilder e Operator SDK
### Anatomia de um controller: watch, reconcile, status
### Quando criar um Operator vs. usar Helm/scripts

# Capítulo 11 — Ecossistema e projeto final
## Empacotamento e entrega
### Helm: charts, values e releases
### Kustomize: overlays por ambiente
## Introdução a GitOps
### Conceito e fluxo com ArgoCD ou Flux (visão geral)
## Projeto final (capstone)
### Provisionar um cluster de 3+ nós com kubeadm
### Fazer deploy de uma aplicação completa (frontend + API + banco via Operator)
### Expor via Ingress com TLS, configurar HPA e NetworkPolicies
### Simular falha de um nó e demonstrar a recuperação
## Próximos passos
### Certificações: KCNA, CKA, CKAD
### Tópicos avançados: service mesh, multi-cluster, admission webhooks
