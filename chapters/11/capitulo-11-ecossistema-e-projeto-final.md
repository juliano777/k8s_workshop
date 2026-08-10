# Capítulo 11 — Ecossistema e projeto final

> **Objetivos de aprendizagem**
> Ao final deste capítulo, você será capaz de:
> 1. Empacotar e distribuir aplicações com Helm: charts, values e o ciclo de releases.
> 2. Gerenciar variações por ambiente com Kustomize: bases e overlays.
> 3. Explicar o modelo GitOps e o funcionamento de ArgoCD/Flux.
> 4. Executar o projeto final: um sistema completo, seguro e resiliente sobre o seu cluster de 3+ nós.
> 5. Traçar seu caminho pós-curso: certificações (KCNA, CKA, CKAD) e os territórios avançados.

> **O capítulo do fechamento.** Ao longo do curso, um problema cresceu silenciosamente: seus YAMLs se multiplicaram. O `web.yaml` do Capítulo 2 virou dezenas de manifestos — com valores que mudam por ambiente, ordem de aplicação, e a eterna pergunta "o que exatamente está rodando em produção?". Este capítulo resolve o problema em três degraus (empacotar → variar → sincronizar) e então entrega o palco do projeto final: **tudo que você aprendeu, de uma vez, funcionando junto**.

---

## 11.1 Empacotamento e entrega

### 11.1.1 Helm: charts, values e releases

O **Helm** é o "gerenciador de pacotes do Kubernetes" — o apt/brew dos clusters. Você já o usou duas vezes como consumidor (kube-prometheus-stack no Capítulo 9); agora, o modelo completo, em três conceitos:

**Chart** — o pacote: uma estrutura de diretórios com manifestos **templatizados**:

```
meu-app/
├── Chart.yaml          # metadados: nome, versão do chart, versão do app
├── values.yaml         # os "botões" configuráveis e seus padrões
├── templates/          # os manifestos com placeholders
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   └── _helpers.tpl    # funções/labels reutilizáveis
└── charts/             # dependências (subcharts)
```

**Values** — a parametrização. O template referencia valores; cada instalação os sobrepõe:

```yaml
# templates/deployment.yaml (trecho)
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    spec:
      containers:
      - name: {{ .Chart.Name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
```

```yaml
# values.yaml (padrões sensatos)
replicaCount: 2
image:
  repository: loja/api
  tag: "2.4.1"                # NUNCA latest — Capítulos 5 e 8 mandaram lembranças
resources:
  requests: { cpu: 100m, memory: 128Mi }   # Capítulo 7 idem
  limits:   { memory: 256Mi }
```

**Release** — uma **instalação nomeada** de um chart num namespace, com histórico de revisões. É o que permite o mesmo chart virar `api-dev`, `api-prod`... cada um com seus values:

```bash
# O ciclo de vida completo:
helm create meu-app                              # scaffolding inicial
helm template meu-app ./meu-app                  # renderiza SEM aplicar (inspecione!)
helm install api-dev ./meu-app -f values-dev.yaml -n dev
helm upgrade api-dev ./meu-app -f values-dev.yaml -n dev   # mudou algo? upgrade
helm list -n dev                                 # releases e revisões
helm rollback api-dev 1 -n dev                   # voltar a uma revisão (lembra o
                                                 #  rollout undo do Cap. 3? mesmo espírito,
                                                 #  escopo maior: o pacote inteiro)
helm uninstall api-dev -n dev
```

E como consumidor de charts públicos (o uso mais frequente):

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm search repo nginx
helm show values bitnami/nginx > valores.yaml    # ★ SEMPRE inspecione antes:
helm install web bitnami/nginx -f meus-valores.yaml   # os values são o contrato
```

**Quando o Helm brilha e onde dói** — a avaliação honesta:

- Brilha: distribuir software para terceiros (todo projeto sério publica um chart), aplicações com **muitos** botões de configuração, dependências entre pacotes, rollback de release.
- Dói: templates Go em YAML ficam ilegíveis rapidamente (`{{- if .Values... }}` aninhados são um dialeto próprio); depurar exige `helm template` constante; e o "estado da release" mora em Secrets no cluster — mais uma fonte de verdade para conciliar.
- Detalhe herdado do Capítulo 10: Helm instala CRDs (pasta `crds/`), mas **não as atualiza** em upgrades — as notas de release dos operators existem por isso.

### 11.1.2 Kustomize: overlays por ambiente

O **Kustomize** ataca o mesmo problema (variação por ambiente) com filosofia oposta: **nada de templates** — YAML puro e válido, com **patches declarativos** por cima. E vem **embutido no kubectl** (`kubectl apply -k`).

A estrutura mental: uma **base** (o manifesto completo e funcional) + **overlays** (só as diferenças de cada ambiente):

```
meu-app/
├── base/
│   ├── kustomization.yaml       # lista os recursos da base
│   ├── deployment.yaml          # YAML normal, sem placeholders!
│   ├── service.yaml
│   └── ingress.yaml
└── overlays/
    ├── dev/
    │   └── kustomization.yaml   # "use a base, com estas diferenças"
    └── prod/
        ├── kustomization.yaml
        └── patch-replicas.yaml  # só o que MUDA em prod
```

```yaml
# base/kustomization.yaml
resources:
- deployment.yaml
- service.yaml
- ingress.yaml
```

```yaml
# overlays/prod/kustomization.yaml
resources:
- ../../base
namespace: loja-prod                 # tudo da base cai neste namespace
namePrefix: prod-                    # e ganha este prefixo
labels:
- pairs: { environment: prod }       # labels em tudo (Capítulo 3 aprovaria)
  includeSelectors: true
images:
- name: loja/api
  newTag: "2.4.1"                    # troca de tag sem tocar na base
patches:
- path: patch-replicas.yaml          # patch estratégico: só os campos alterados
```

```yaml
# overlays/prod/patch-replicas.yaml — repare: é um "fragmento" de Deployment
apiVersion: apps/v1
kind: Deployment
metadata: { name: api }
spec:
  replicas: 5                        # dev usa o default da base; prod, 5
```

```bash
kubectl kustomize overlays/prod      # renderiza (inspecione, como no helm template)
kubectl apply -k overlays/prod       # aplica
kubectl diff -k overlays/prod        # o velho amigo do Capítulo 2, em modo kustomize
```

**Helm × Kustomize — a decisão (e a não-decisão):**

| | Helm | Kustomize |
|---|---|---|
| Filosofia | templates + values | base + patches |
| YAML fica | com placeholders (inválido sozinho) | sempre válido e aplicável |
| Curva | maior (dialeto de template) | menor (é só YAML + kustomization) |
| Distribuir p/ terceiros | **excelente** (repos, versões, deps) | fraco (não é pacote) |
| Variar SEUS apps por ambiente | ok, mas verboso | **excelente** |
| Rollback embutido | sim (releases) | não (delega ao Git/GitOps) |

E a não-decisão: **os dois convivem** o tempo todo — o padrão de mercado é consumir software de terceiros via **Helm** e gerenciar as próprias aplicações via **Kustomize** (inclusive kustomizando a *saída* de um chart quando preciso). O projeto final usa exatamente essa combinação.

**Exercício de fixação 11.1**
1. Explique "chart, values, release" com a analogia de um instalador de software: o que corresponde a quê?
2. Por que `helm show values` antes de instalar é o equivalente Helm do "leia o RBAC antes de instalar o operator" (Capítulo 10)?
3. Converta mentalmente: seu `web.yaml` do Capítulo 2 precisa de 2 réplicas em dev e 6 em prod, com tags de imagem diferentes. Esboce a árvore Kustomize (base + 2 overlays) e o conteúdo do patch de prod.
4. Defenda a combinação "Helm para terceiros, Kustomize para os seus" com um argumento por ferramenta.

---

## 11.2 Introdução a GitOps

### 11.2.1 Conceito e fluxo com ArgoCD ou Flux (visão geral)

Falta o último degrau. Helm e Kustomize geram os manifestos certos — mas **quem os aplica?** Se a resposta é "uma pessoa com kubectl" ou "o pipeline de CI com um kubeconfig", dois problemas persistem:

1. **Drift**: alguém roda um `kubectl edit` de emergência às 3h... e o Git mente para sempre sobre o que está em produção.
2. **Credenciais espalhadas**: cada pipeline com um kubeconfig poderoso (o Capítulo 8 franze a testa).

**GitOps** é a resposta, em quatro princípios (formalizados pelo OpenGitOps/CNCF):

1. **Declarativo**: todo o estado desejado descrito como dados (você vive isso desde o Capítulo 2).
2. **Versionado e imutável**: o Git como fonte única da verdade — história, revisão, blame, revert.
3. **Puxado automaticamente**: um **agente no cluster** observa o repositório e traz as mudanças (*pull*), em vez de o CI empurrar (*push*). O kubeconfig não sai do cluster.
4. **Continuamente reconciliado**: o agente compara Git × cluster **para sempre** e corrige divergências.

Leia o princípio 4 de novo. É **o loop de reconciliação do Capítulo 1** — o mesmo desenho, um nível acima:

```
   controllers:   spec (etcd)  ──loop──▶  estado do cluster
   GitOps:        Git (repo)   ──loop──▶  spec (etcd)  ──loop──▶  estado do cluster
```

O Git virou o "etcd dos humanos". O curso fecha o círculo conceitual: **é reconciliação até lá em cima**.

**As duas ferramentas (a mesma ideia, ênfases diferentes):**

- **ArgoCD**: o mais adotado; UI web excelente (a árvore de recursos ao vivo — Deployment→RS→Pods do Capítulo 3, desenhada); conceito central: **Application** (um CR! — Capítulo 10 em ação) que liga *repo+path+revisão* → *cluster+namespace*.
- **Flux**: nativo de CRDs "puras" (GitRepository, Kustomization, HelmRelease), mais unix-like, forte automação de atualização de imagens. Sem UI própria (usa-se Weave GitOps/monitoring).

Ambos: suportam Helm e Kustomize como fonte, detectam drift, e oferecem **sync automático + self-heal + prune** (apagar do cluster o que sumiu do Git — o delete declarativo que faltava).

**O fluxo do dia a dia, de ponta a ponta:**

```
dev abre PR (muda a tag da imagem no overlay de prod)
  → revisão + aprovação (o "change management" virou pull request)
  → merge na main
  → ArgoCD detecta (~3 min ou webhook) → OutOfSync
  → sync: kubectl apply do que mudou → rolling update (Cap. 3) → Synced/Healthy
  → alguém roda kubectl edit no cluster? → drift detectado → self-heal REVERTE
```

O gesto de deploy desapareceu: **deploy = merge**. Rollback = `git revert` (+ sync). Auditoria = `git log`. E o experimento mental que consolida: com GitOps + self-heal, o `kubectl edit` heroico do plantonista é *desfeito pelo robô* — a mudança de emergência também tem que ir pelo Git (ou pausar o sync — decisão consciente e registrada).

**Prova rápida de conceito com ArgoCD** (o projeto final aprofunda):

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl get pods -n argocd
# senha inicial do admin (um Secret, claro):
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl port-forward svc/argocd-server -n argocd 8080:443    # UI em https://localhost:8080
```

```yaml
# Uma Application apontando para o SEU repositório do projeto final:
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: loja
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/voce/projeto-final.git
    targetRevision: main
    path: overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: loja-prod
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
```

> **E o CI?** GitOps não o substitui — reparte papéis: o **CI** testa, constrói, escaneia (Trivy!), assina (cosign — Capítulo 8) e **atualiza a tag no repo de manifests**; o **CD (agente GitOps)** leva ao cluster. A ponte entre os dois é um commit.

**Exercício de fixação 11.2**
1. Enuncie os 4 princípios GitOps e aponte qual deles é "o loop de reconciliação do Capítulo 1 promovido de nível".
2. Push (CI aplica com kubeconfig) vs. pull (agente no cluster): dê uma vantagem de segurança e uma de consistência do modelo pull.
3. Com self-heal ativo, o que acontece com um `kubectl scale deploy api --replicas=10` manual? Isso é bug ou feature? Como escalar "de verdade"?
4. Descreva o caminho completo de um hotfix (imagem 2.4.2) da abertura do PR ao Pod rodando — nomeando a ferramenta responsável por cada trecho (CI, Git, ArgoCD, Deployment controller).

---

## 11.3 Projeto final (capstone)

> **As regras do jogo**: (1) tudo declarativo, versionado num repositório Git — a rigor, ao final, `git clone` + bootstrap do ArgoCD deve reconstruir o sistema inteiro; (2) cada fase tem **critérios de aceite** — trate-os como a prova prática do curso; (3) documente um `README.md` com decisões e um `RUNBOOK.md` com operações (o Capítulo 9 lhe deu o formato). Tempo estimado: 1–2 dias de trabalho focado.
>
> **A aplicação**: uma loja mínima — `frontend` (web) + `api` (REST) + PostgreSQL. Use qualquer app de exemplo que conheça (ou o par nginx + um backend simples); o Kubernetes em volta é o que está sendo avaliado.

### 11.3.1 Fase 1 — Provisionar um cluster de 3+ nós com kubeadm

Reexecute o Capítulo 6 — agora sem consultar o capítulo a cada passo (consulte seu script e seu runbook; é para isso que existem):

- 3 máquinas preparadas via `prepara-no.sh` versionado no repo.
- `kubeadm init` (CIDRs planejados, `--control-plane-endpoint`) + Calico + 2 joins.
- Complementos que o projeto exigirá (cada um, você já instalou antes): **local-path-provisioner** (StorageClass default — Cap. 5/6), **Ingress-NGINX** (Cap. 4/6), **metrics-server** (Cap. 7), **kube-prometheus-stack** (Cap. 9), **cert-manager** e **CloudNativePG** (Cap. 10), **ArgoCD** (11.2).

**Critérios de aceite:**
- [ ] `kubectl get nodes` → 3 Ready; `kubectl get sc` → default marcada
- [ ] Os 5 testes de validação do 6.2.5 passam
- [ ] Snapshot do etcd agendado (CronJob — Desafio 6.4) e **um restore testado**
- [ ] Repositório com: scripts, manifests de bootstrap e o RUNBOOK iniciado

### 11.3.2 Fase 2 — Deploy da aplicação completa (frontend + API + banco via Operator)

Estruture o repositório no padrão da seção 11.1 (base + overlays; um overlay `prod` basta, mas deixe `dev` esboçado para provar o modelo):

```
projeto-final/
├── bootstrap/            # ArgoCD Applications (a "raiz" do GitOps)
├── infra/                # issuers do cert-manager, ServiceMonitors, PDBs...
├── apps/
│   ├── base/             #   frontend, api (Deployments, Services, ConfigMaps)
│   └── overlays/prod/
└── banco/                # o CR Cluster do CloudNativePG + Secrets (selados!)
```

Exigências técnicas (o checklist dos capítulos):

- **Banco**: CR `Cluster` do CNPG, `instances: 3`; app conecta no Service `-rw` **por nome DNS** (Cap. 4/5); credenciais consumidas do Secret gerado pelo operator — e qualquer Secret seu vai **selado** (Sealed Secrets) ou referenciado (ESO), nunca em claro no Git (Cap. 8).
- **API e frontend**: Deployments com **probes** completas (startup/liveness/readiness — Cap. 3), **requests/limits** (Cap. 7), **SecurityContext endurecido** e namespace com **PSS restricted** (Cap. 8), **anti-affinity/topologySpread** entre réplicas (Cap. 7), **PDB** (`maxUnavailable: 1`) para cada um.
- **Entrega**: tudo chega ao cluster **via ArgoCD** (Application(s) apontando para o repo). Prove: mude a tag da imagem por commit e assista ao rollout sem tocar no kubectl.

**Critérios de aceite:**
- [ ] `kubectl get cluster` → 3 instâncias, 1 primária; app lê/grava no banco
- [ ] ArgoCD: tudo Synced/Healthy; um `kubectl edit` manual é revertido (self-heal)
- [ ] `kubectl get pods -o wide` → réplicas espalhadas entre workers
- [ ] Nenhum segredo em claro no Git (inspecione o histórico!)

### 11.3.3 Fase 3 — Ingress com TLS, HPA e NetworkPolicies

**Exposição (Cap. 4 + 10):** Ingress com regras por host (`loja.<seu-domínio-ou-nip.io>`), TLS emitido pelo **cert-manager** (ClusterIssuer self-signed no lab; ACME se tiver domínio real) — e o teste de fogo: delete o Secret TLS e confirme a recriação automática.

**Elasticidade (Cap. 7):** HPA na API (CPU, min 2 / max 6, janela de estabilização) — e a prova de carga: gere tráfego, assista `kubectl get hpa -w` subir e o Grafana desenhar (Cap. 9).

**Isolamento (Cap. 8):** o conjunto default-deny + aberturas mínimas:

```
ingress-nginx ─▶ frontend ─▶ api ─▶ pg (5432)      [+ todos ─▶ kube-dns]
```

E os testes negativos que valem mais que os positivos: um Pod intruso **não** alcança o banco; o frontend **não** fala com o banco diretamente; nada esquece o DNS.

**Critérios de aceite:**
- [ ] `curl -k https://loja...` → 200 via Ingress; certificado gerido pelo cert-manager
- [ ] HPA escala sob carga e retorna após a janela; gráfico capturado no Grafana
- [ ] Matriz de conectividade testada (positivos E negativos) e documentada no README

### 11.3.4 Fase 4 — Simular falha de um nó e demonstrar a recuperação

O gran finale — a cena do Capítulo 1, agora sobre um sistema completo e **sob observação**:

**Preparação**: dashboard do Grafana aberto (Pods por nó, latência do Ingress), `kubectl get pods -o wide -w` e `kubectl get cluster pg-loja -w` em terminais, e um gerador de carga contínuo batendo no Ingress (para medir impacto real no usuário).

**O experimento** (escolha o nó que hospeda o **primário do banco** — máximo drama):

1. `poweroff` abrupto na VM do worker escolhido. Cronometre.
2. Observe e **anote a linha do tempo**: nó NotReady (~40s) → taint not-ready (Cap. 7) → CNPG promove réplica (segundos — Cap. 10) → após ~5 min, Pods stateless realocados (tolerationSeconds — Cap. 7) → HPA/PDB mantendo o serviço → curvas do Grafana contando a história (Cap. 9).
3. Meça no gerador de carga: houve erros? Por quantos segundos? (A resposta honesta: a janela do failover do banco — e ela é pequena.)
4. Religue o nó: reintegração automática; CNPG reconstrói a réplica perdida.
5. **Escreva o post-mortem** (1 página): linha do tempo, o que cada mecanismo fez, o que você ajustaria (tolerationSeconds menores? mais réplicas? PDB diferente?).

**E o teste final de GitOps**: destrua tudo (`kubectl delete namespace loja-prod`) e recupere **apenas sincronizando o ArgoCD**. Se o sistema renasce do Git (com os dados do banco vindos do backup do CNPG, se você configurou o bônus), o círculo está completo.

**Critérios de aceite:**
- [ ] Post-mortem escrito, com linha do tempo medida e melhorias propostas
- [ ] Janela de indisponibilidade do banco < 1 min; stateless realocado sem intervenção
- [ ] Reconstrução via Git demonstrada

> **Bônus para os insaciáveis**: backup contínuo do CNPG para um MinIO no cluster + restore point-in-time; canary com Argo Rollouts (Cap. 7); assinar as imagens com cosign e exigi-las via política (Cap. 8); converter o cluster para HA com uma 4ª máquina (Cap. 6).

---

## 11.4 Próximos passos

### 11.4.1 Certificações: KCNA, CKA, CKAD

As certificações da CNCF/Linux Foundation são respeitadas justamente por serem **práticas** (exceto a KCNA): terminal real, cluster real, tempo apertado. Onde você está após este curso:

| | KCNA | CKAD | CKA |
|---|---|---|---|
| Formato | múltipla escolha, 90 min | prática, 2h | prática, 2h |
| Foco | panorama cloud-native | **desenvolver** para K8s (Caps. 2–5, 7) | **administrar** K8s (Caps. 2–9, ênfase no 6!) |
| Público | iniciantes, gestores, comercial | devs | SREs, sysadmins, DevOps |
| Após este curso | sobra preparo | falta só treino de velocidade | o curso foi desenhado com ela no horizonte |

Recomendações de quem terminou este curso:

- **Vá de CKA** se o seu caminho é infraestrutura/SRE — o Capítulo 6 (kubeadm, etcd backup/restore, upgrade, troubleshooting de nós) é o coração da prova; **CKAD** se é desenvolvimento — e os dois se sobrepõem bastante.
- O diferencial na prova é **velocidade**: `kubectl` imperativo com `--dry-run=client -o yaml` (Cap. 2), aliases, `kubectl explain` em vez de documentação, e o método de troubleshooting do Cap. 9 no reflexo.
- Treine em simuladores (killer.sh acompanha a inscrição; killercoda para cenários) cronometrando. A prova permite a documentação oficial aberta — saiba *navegar* nela, não decorá-la.
- Ordem sugerida: direto na CKA/CKAD (a KCNA só se precisar da credencial rápida ou for de área adjacente). Depois delas: **CKS** (segurança — o Capítulo 8 é o trailer) exige a CKA como pré-requisito.

### 11.4.2 Tópicos avançados: service mesh, multi-cluster, admission webhooks

O mapa dos territórios que este curso margeou — cada um com o gancho que você já tem:

**Service mesh (Istio, Linkerd, Cilium Service Mesh).** O gancho: o exercício do Capítulo 4 ("o tráfego interno após o TLS terminar no Ingress é claro?") e os sidecars do Capítulo 3. Um mesh injeta proxies (ou usa eBPF/ambient) para dar, sem tocar no código: **mTLS automático** entre todos os serviços, políticas L7, retries/timeouts/circuit breaking, e telemetria por requisição (os traces do Cap. 9). Custo real: complexidade operacional — adote por necessidade, não por moda. Comece pelo Linkerd (o minimalista) num cluster de estudo.

**Multi-cluster e federação.** O gancho: a Topologia B do Capítulo 6 protege contra falha de nó — e contra a falha da *região*? Padrões: clusters por região/ambiente com GitOps multiplicando os manifests (o ArgoCD ApplicationSet é o caminho natural a partir do seu projeto final), balanceamento global de tráfego, e **Cluster API** (Cap. 6.3.2) para criar clusters declarativamente. É também a fronteira de plataforma interna (IDP/Backstage) — Kubernetes como produto para os times.

**Admission webhooks.** O gancho: o terceiro portão do Capítulo 8 e a pergunta "como o CNPG injeta defaults nos CRs?". Webhooks **validating** (rejeitam com regras suas) e **mutating** (alteram objetos em voo — é assim que meshes injetam sidecars e operators aplicam defaults) são o mecanismo por trás de Kyverno/Gatekeeper e dos conversion webhooks do Cap. 10. Escrever um (Kubebuilder os gera) é o passo natural depois do seu primeiro operator — e o poder exige juízo: um webhook mal escrito pode travar o cluster inteiro (estude `failurePolicy`).

**E o hábito que sustenta tudo**: o Kubernetes lança 3 versões por ano. Acompanhe as release notes (o 6.4.2 ensinou por quê), o blog da CNCF, e — melhor investimento — **opere continuamente o seu cluster do Capítulo 6**: upgrades reais a cada release, um app pessoal rodando, o runbook crescendo. Conhecimento de Kubernetes evapora sem cluster para exercê-lo.

---

## Encerramento do curso

Olhe a distância percorrida. No Capítulo 1, "orquestração" era uma promessa abstrata; hoje você tem um repositório Git de onde renasce, com um comando de sync, um sistema distribuído completo — três nós que você mesmo uniu com kubeadm, um banco que sobrevive à morte do seu primário, TLS que se renova sozinho, tráfego trancado por padrão, métricas contando a história e um post-mortem escrito com dados.

Mais importante que as ferramentas, você levou o **modelo mental**: estado desejado, loops de reconciliação, tudo declarativo, tudo versionado — do container ao GitOps, é a mesma ideia em escalas crescentes. As ferramentas mudarão de nome; a ideia vai durar.

O cluster está no ar. O resto é operação — e agora, operação é com você.

---

## Resumo do capítulo

- **Helm** empacota (chart = templates + values; release = instalação com histórico e rollback) — imbatível para distribuir e consumir software de terceiros (`show values` antes, sempre); **Kustomize** varia os seus apps por ambiente (base + overlays + patches, YAML sempre válido, embutido no kubectl). O padrão de mercado usa **os dois**.
- **GitOps** = declarativo + versionado + **pull** por agente + **reconciliação contínua** — o loop do Capítulo 1 promovido: Git → etcd → cluster. **ArgoCD** (Applications, UI, self-heal/prune) ou **Flux**; deploy vira merge, rollback vira revert, drift é revertido pelo robô; o CI constrói e commita, o agente entrega.
- O **projeto final** integra tudo: cluster kubeadm 3 nós + complementos → app completa com banco via CNPG, entregue por GitOps, com probes/recursos/PSS/anti-affinity/PDB → Ingress+TLS (cert-manager), HPA sob carga, NetworkPolicies com testes negativos → falha real de nó com post-mortem medido e reconstrução a partir do Git.
- Depois: **CKA** (ou CKAD) com treino de velocidade — este curso cobre o conteúdo; e os territórios avançados com seus ganchos: **service mesh** (mTLS/L7 — Caps. 3–4), **multi-cluster** (GitOps em escala — Caps. 6, 11), **admission webhooks** (o motor do Cap. 8 e dos operators do Cap. 10). E o hábito: opere seu cluster, versão após versão.
