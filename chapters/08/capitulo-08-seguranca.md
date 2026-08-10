# Capítulo 8 — Segurança

> **Objetivos de aprendizagem**
> Ao final deste capítulo, você será capaz de:
> 1. Explicar como o Kubernetes autentica usuários e workloads, e o papel das ServiceAccounts.
> 2. Construir autorização com RBAC: Roles, ClusterRoles, RoleBindings e ClusterRoleBindings.
> 3. Endurecer containers com SecurityContext e aplicar Pod Security Standards por namespace.
> 4. Isolar tráfego com NetworkPolicies, partindo de um default-deny.
> 5. Descrever soluções maduras de gestão de secrets (Sealed Secrets, External Secrets, Vault).
> 6. Explicar o básico de segurança de supply chain: scan de imagens, assinatura e boas práticas de build.

> **Fio condutor do capítulo — defesa em profundidade**: nenhuma camada é suficiente sozinha; cada seção adiciona uma. Pense como um atacante: para causar dano ele precisa (1) de credenciais ou de um container invadido, (2) de permissões para agir, (3) de privilégios no host e (4) de rede para se mover. Vamos fechar cada porta nessa ordem.

---

## 8.1 Autenticação e autorização

Toda requisição ao API server (Capítulo 1: a porta única) atravessa três portões, nesta ordem:

```
requisição ─▶ AUTENTICAÇÃO (quem é você?) ─▶ AUTORIZAÇÃO (pode fazer isso?) ─▶ ADMISSION (regras extras) ─▶ etcd
                   401 se falhar                 403 se falhar                   rejeição/mutação
```

**Quem é "você"?** O Kubernetes reconhece dois tipos de identidade:

- **Usuários humanos** — o Kubernetes **não tem** objeto "User" nem banco de usuários! A identidade vem de fora: certificados de cliente (o que o admin.conf do Capítulo 6 usa — o CN do certificado é o nome, os grupos vêm do campo O), tokens OIDC (integração com Google/Azure AD/Keycloak — o padrão corporativo) ou os mecanismos das nuvens (IAM no EKS etc.).
- **Workloads (Pods)** — estes sim têm identidade nativa: as **ServiceAccounts**.

### 8.1.1 ServiceAccounts

Uma **ServiceAccount (SA)** é a identidade que um Pod usa para falar com o API server. Todo namespace nasce com uma SA `default`, e todo Pod que não declara nada **roda como ela**:

```bash
kubectl get serviceaccounts
kubectl run teste --image=nginx:1.27
kubectl get pod teste -o jsonpath='{.spec.serviceAccountName}'   # default
```

Como a identidade chega ao Pod: o kubelet monta em `/var/run/secrets/kubernetes.io/serviceaccount/` um **token** (JWT), o CA do cluster e o namespace. Qualquer processo no container pode usá-los para chamar a API:

```bash
kubectl exec teste -- sh -c \
 'TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token); \
  curl -s --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  -H "Authorization: Bearer $TOKEN" https://kubernetes.default.svc/api/v1/namespaces/default/pods'
# Resposta: 403 Forbidden — autenticou (sabe quem é), mas NÃO autorizou.
# Esse 403 é uma boa notícia: a SA default não tem permissões. RBAC funcionando.
```

> **Nota de evolução**: hoje esses tokens são **projetados** — expiram, são rotacionados automaticamente e vinculados ao Pod (se o Pod morre, o token morre). Nas versões antigas eram Secrets eternos; se encontrar material antigo ensinando a "pegar o token do Secret da SA", saiba que esse modelo foi aposentado por inseguro.

**Boas práticas de SA — três regras:**

1. **Uma SA por aplicação** que precise falar com a API (nunca acumular permissões na `default`):
   ```bash
   kubectl create serviceaccount api-pedidos
   ```
   ```yaml
   spec:
     serviceAccountName: api-pedidos
   ```
2. **A maioria das aplicações não fala com a API** — desligue a montagem do token e elimine a superfície de ataque:
   ```yaml
   spec:
     automountServiceAccountToken: false
   ```
3. SAs também são a ponte para identidades **externas**: workload identity nas nuvens (a SA do Pod "vira" um papel IAM — sem chaves de nuvem em Secrets). Guarde o conceito; é o padrão moderno.

### 8.1.2 RBAC: Roles, ClusterRoles e bindings

Autenticado ≠ autorizado. O **RBAC (Role-Based Access Control)** responde à segunda pergunta com uma gramática de quatro objetos — dois definem **o que pode ser feito**, dois definem **quem pode**:

```
      O QUÊ (permissões)                 QUEM (vínculo)
┌──────────────────────────┐   ┌───────────────────────────────┐
│ Role         (namespace) │◀──│ RoleBinding        (namespace)│
│ ClusterRole  (cluster)   │◀──│ ClusterRoleBinding (cluster)  │
└──────────────────────────┘   └───────────────────────────────┘
        regras = recursos × verbos      sujeitos = users, groups, SAs
```

**Role** — permissões dentro de **um namespace**:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: loja-prod
  name: leitor-de-pods
rules:
- apiGroups: [""]                    # "" = API core (pods, services, configmaps...)
  resources: ["pods", "pods/log"]    # sub-recursos contam! (log, exec, port-forward)
  verbs: ["get", "list", "watch"]    # os verbos de leitura
```

Os **verbos**: `get`, `list`, `watch` (leitura), `create`, `update`, `patch`, `delete` (escrita). E um detalhe que derruba auditorias: **sub-recursos** como `pods/exec` são permissões separadas — dar `create` em `pods/exec` é dar shell nos containers; trate como privilégio alto.

**RoleBinding** — liga a Role a sujeitos:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: loja-prod
  name: devs-leem-pods
subjects:
- kind: User
  name: ana@empresa.com              # vem da autenticação (OIDC/cert)
- kind: Group
  name: time-loja                    # grupos: o jeito escalável
- kind: ServiceAccount
  name: api-pedidos
  namespace: loja-prod
roleRef:
  kind: Role
  name: leitor-de-pods
  apiGroup: rbac.authorization.k8s.io
```

**ClusterRole / ClusterRoleBinding** — a mesma ideia em escopo de **cluster**, necessários para: recursos não-namespaced (nodes, PVs, namespaces — Capítulo 3), permissões em **todos** os namespaces, e endpoints não-recurso. O cluster já traz ClusterRoles prontas — conheça as quatro:

```bash
kubectl get clusterroles | grep -E '^(cluster-admin|admin|edit|view) '
# cluster-admin  → tudo, em tudo (o poder do admin.conf do Capítulo 6)
# admin          → quase tudo dentro de um namespace (inclusive RBAC local)
# edit           → cria/edita objetos comuns, não mexe em RBAC
# view           → somente leitura, sem ver Secrets (repare na sensatez!)
```

**O padrão mais útil do RBAC** — ClusterRole + **RoleBinding**: define a permissão uma vez, aplica namespace a namespace:

```bash
# O time da loja pode editar objetos, mas SÓ no namespace deles:
kubectl create rolebinding loja-editores \
  --clusterrole=edit --group=time-loja --namespace=loja-prod
```

**Depuração e auditoria — os dois comandos de ouro:**

```bash
# "Eu posso...?" / "Fulano pode...?"
kubectl auth can-i delete pods -n loja-prod
kubectl auth can-i create deployments -n loja-prod --as=ana@empresa.com
kubectl auth can-i list secrets --as=system:serviceaccount:default:api-pedidos

# "Quem pode...?" (requer o plugin kubectl-who-can, do ecossistema)
kubectl who-can delete pods -n loja-prod
```

**Princípios que separam RBAC bom de RBAC teatral:**

- **Menor privilégio**: comece do zero e adicione; nunca comece de cluster-admin e "depois restrinjo".
- **RBAC é allow-only**: não existe regra de negação — o que não foi concedido está negado. Isso simplifica auditar: basta listar bindings.
- **Grupos > usuários** nos bindings (pessoas entram e saem; papéis ficam).
- Cuidado com **escalada indireta**: quem pode `create pods` num namespace pode criar um Pod usando *qualquer SA daquele namespace* — herdando as permissões dela. Permissões de criar workloads e SAs poderosas devem andar juntas na análise.
- O acesso de `get` em Secrets é leitura de senhas (Capítulo 5!). A ClusterRole `view` não o inclui por bom motivo; seus papéis customizados devem seguir o exemplo.

**Exercício de fixação 8.1**
1. Por que o Kubernetes não tem objeto "User"? De onde vêm os usuários humanos em uma empresa típica?
2. O experimento do `curl` com o token da SA default retornou 403, não 401. Explique a diferença e por que o 403 é o comportamento desejado.
3. Escreva (YAML) a Role + RoleBinding para que a SA `backup-bot` do namespace `infra` possa apenas `get/list` PVCs e `create` snapshots de etcd... espere: snapshots de etcd não passam pela API do Kubernetes! O que isso revela sobre o alcance do RBAC? (Reflexão do Desafio 6.4.)
4. Um estagiário recebeu `edit` no cluster inteiro "para agilizar". Cite dois riscos concretos e o binding correto para dar `edit` apenas em `dev`.
5. Por que conceder `create` em `pods/exec` é quase equivalente a conceder as permissões das SAs do namespace? Trace o caminho da escalada.

---

## 8.2 Segurança de workloads

RBAC protege a API. Mas e se o atacante entra **pela aplicação** (uma RCE no seu app)? A pergunta vira: *o que ele consegue fazer de dentro do container?* Duas camadas respondem: privilégios do processo (SecurityContext) e alcance de rede (NetworkPolicies).

### 8.2.1 SecurityContext e Pod Security Standards

**SecurityContext** define os privilégios do processo — no nível do Pod (vale para todos os containers) e/ou do container (sobrepõe). O manifesto endurecido de referência, linha a linha:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: api-endurecida
spec:
  securityContext:                     # nível POD
    runAsNonRoot: true                 # recusa imagens que rodem como root
    runAsUser: 10001                   # UID não-privilegiado explícito
    fsGroup: 10001                     # grupo dono dos volumes montados
    seccompProfile:
      type: RuntimeDefault             # filtra syscalls perigosas (padrão sensato)
  containers:
  - name: app
    image: loja/api:2.4.1
    securityContext:                   # nível CONTAINER
      allowPrivilegeEscalation: false  # bloqueia setuid/ganho de privilégio
      readOnlyRootFilesystem: true     # filesystem imutável (Capítulo 1 levado a sério)
      capabilities:
        drop: ["ALL"]                  # remove TODAS as capabilities do kernel
        # add: ["NET_BIND_SERVICE"]    # devolva só o estritamente necessário
    volumeMounts:
    - name: tmp                        # com root FS read-only, dê um /tmp gravável
      mountPath: /tmp
  volumes:
  - name: tmp
    emptyDir: {}
```

Por que cada linha importa (a mentalidade, não a decoreba):

- **Container invadido rodando como root** + alguma fresta = potencialmente **root no nó** (o kernel é compartilhado — Capítulo 1). `runAsNonRoot` + `runAsUser` cortam esse caminho na raiz. (Dica de build: defina `USER 10001` no Dockerfile; imagens oficiais cada vez mais já vêm assim.)
- **Capabilities** são os "pedaços de root" do Linux (abrir porta <1024, mexer na rede...). `drop: ALL` e devolver só o necessário é o menor privilégio aplicado ao kernel.
- **readOnlyRootFilesystem** transforma a imagem imutável em *runtime* imutável: o invasor não grava binários nem altera o app. Efeito colateral saudável: força a disciplina de escrever só em volumes explícitos.
- **E o oposto de tudo isso**: `privileged: true` — desliga o isolamento (acesso total ao host). Legítimo em pouquíssimos casos de infraestrutura (o Calico do Capítulo 6, por exemplo); num app comum, é alarme de incêndio.

**Pod Security Standards (PSS) — a política que impõe o padrão.** Confiar que todo manifesto virá endurecido não escala. Os PSS definem três perfis e o **Pod Security Admission** (aquele terceiro portão, *admission*, embutido no API server) os aplica **por namespace**, via labels:

| Perfil | Ideia | Uso típico |
|---|---|---|
| **privileged** | sem restrições | namespaces de infra (CNI, storage) |
| **baseline** | bloqueia o sabidamente perigoso (privileged, hostPath livre, hostNetwork...) | mínimo para apps |
| **restricted** | endurecimento máximo (exige runAsNonRoot, drop ALL, seccomp...) | **o alvo para produção** |

```bash
kubectl label namespace loja-prod \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted
```

Os três **modos** são a arma da adoção gradual: `warn` (avisa no kubectl), `audit` (registra no log de auditoria) e `enforce` (**rejeita** o Pod). Estratégia clássica de migração: `warn`+`audit` em restricted por algumas semanas, corrija o que gritar, então suba o `enforce`.

```bash
# Prova: num namespace restricted, tente um Pod "ingênuo"
kubectl run ingenuo --image=nginx:1.27 -n loja-prod
# Error: violates PodSecurity "restricted": allowPrivilegeEscalation != false, ...
# A mensagem lista exatamente o que falta — é quase um tutorial embutido.
```

> Para políticas além de segurança de Pod (exigir labels, proibir `latest`, limitar registries — Capítulo 5!), o ecossistema usa admission controllers programáveis: **Kyverno** (políticas em YAML) ou **OPA/Gatekeeper**. Fica o mapa; o aprofundamento é pós-curso.

### 8.2.2 NetworkPolicies (isolamento de tráfego)

Hora de pagar duas promessas: a do Capítulo 3 ("namespaces não isolam rede") e a do Capítulo 6 (escolhemos Calico *por causa disto*). Por padrão, a rede do Kubernetes é **plana**: o Pod invadido do frontend alcança o banco de outro time, o etcd... tudo. NetworkPolicies são o firewall declarativo que muda isso.

**Mecânica essencial em três frases:**
1. NetworkPolicies **selecionam Pods** (labels, claro — Capítulo 3) e declaram o que **pode** (allow-only, como o RBAC).
2. Enquanto **nenhuma** policy seleciona um Pod, **tudo é permitido**; a partir da primeira, **só o declarado passa** (para a direção coberta: ingress e/ou egress).
3. Quem aplica é o **CNI** — em Flannel, policies são ignoradas silenciosamente (o pior modo de falhar: você *acha* que está isolado).

**O ponto de partida de toda arquitetura séria — default-deny no namespace:**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: loja-prod
spec:
  podSelector: {}              # seleciona TODOS os Pods do namespace
  policyTypes: [Ingress, Egress]
  # sem regras allow = nada entra, nada sai
```

E então, **abra apenas os fluxos desenhados**. A trinca clássica frontend → api → banco:

```yaml
# 1. O banco só aceita a API:
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: banco-so-da-api
  namespace: loja-prod
spec:
  podSelector:
    matchLabels: { app: pg }
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels: { app: api }
    ports:
    - { protocol: TCP, port: 5432 }
---
# 2. A API pode sair para o banco... e para o DNS (a pegadinha nº 1!):
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-egress
  namespace: loja-prod
spec:
  podSelector:
    matchLabels: { app: api }
  policyTypes: [Egress]
  egress:
  - to:
    - podSelector:
        matchLabels: { app: pg }
    ports:
    - { protocol: TCP, port: 5432 }
  - to:                                    # sem esta regra, NADA resolve nomes:
    - namespaceSelector: {}                # (CoreDNS mora em kube-system!)
      podSelector:
        matchLabels: { k8s-app: kube-dns }
    ports:
    - { protocol: UDP, port: 53 }
    - { protocol: TCP, port: 53 }
```

Gramática dos seletores em `from`/`to` — e a pegadinha sintática mais traiçoeira do YAML de policies:

```yaml
  - from:
    - namespaceSelector: { matchLabels: { team: loja } }
      podSelector: { matchLabels: { app: api } }      # MESMO item = E (api DO namespace loja)
  - from:
    - namespaceSelector: { matchLabels: { team: loja } }
    - podSelector: { matchLabels: { app: api } }      # itens SEPARADOS = OU (todo o ns loja, OU api local)
```

Um traço (`-`) muda o significado de "E" para "OU". Revise policies com esse olho. Há ainda `ipBlock` (CIDRs, para tráfego externo) — e lembre-se: **policies são aditivas** (união de tudo que permite; não existe "negar por cima").

**Teste sempre — política de rede não testada é decoração:**

```bash
kubectl run intruso --rm -it --image=busybox:1.36 -n loja-prod -- \
  sh -c 'nc -zv -w 2 pg 5432'          # deve FALHAR (intruso não é app: api)
kubectl exec deploy/api -n loja-prod -- sh -c 'nc -zv -w 2 pg 5432'   # deve passar
```

> NetworkPolicies cuidam de **quem fala com quem**; criptografia e identidade *do tráfego* (mTLS) são o território dos service meshes (gancho do exercício 4 do Capítulo 4). E os CNIs avançados (Cilium) estendem policies até L7 (por rota HTTP) — o mapa de novo.

**Exercício de fixação 8.2**
1. Ordene as camadas que um atacante com RCE no frontend atravessaria até chegar ao banco de outro namespace — e aponte qual seção deste capítulo fecha cada uma.
2. Por que `readOnlyRootFilesystem: true` quase sempre exige um `emptyDir` em `/tmp`? O que isso força na disciplina da aplicação?
3. Seu Pod endurecido é rejeitado no namespace `restricted` com três violações. Isso é o sistema funcionando ou falhando? Qual a rota de migração recomendada para um namespace legado?
4. Após aplicar default-deny com egress, as aplicações começaram a falhar com erros de resolução de nomes — mas `nc` por IP funciona. Diagnóstico e correção?
5. Escreva a policy: Pods `app: relatorio` do namespace `bi` podem falar com `app: api` em `loja-prod` na porta 8080; nada mais entra na API além disso e do Ingress Controller (namespace `ingress-nginx`). (Dica: labels de namespace.)

---

## 8.3 Boas práticas

As duas últimas portas: os segredos que os workloads carregam e a procedência do que você roda.

### 8.3.1 Gestão de secrets (Sealed Secrets, external secrets — visão geral)

O Capítulo 5 deixou o problema armado: Secrets são a interface universal, mas **base64 não protege nada** e YAML de Secret **não pode ir ao Git** — o que colide de frente com o "tudo declarativo e versionado" que o curso prega (e com o GitOps do Capítulo 11). As soluções maduras resolvem exatamente essa colisão, cada uma com uma filosofia:

**Higiene básica primeiro (sem ferramenta nenhuma):**

- **Encryption at rest** no etcd (Capítulo 6 é onde se configura: `EncryptionConfiguration` no API server) — sem isso, o snapshot de backup do 6.4.3 contém todas as senhas em claro. Releia essa frase.
- **RBAC**: `get secrets` é privilégio alto (8.1.2); a ClusterRole `view` já ensina o caminho.
- Prefira **volume a env** para consumo (5.1.3) e `automountServiceAccountToken: false` onde couber.

**Sealed Secrets (Bitnami) — "criptografe para o Git".**
Um controller no cluster detém um par de chaves. A CLI `kubeseal` criptografa seu Secret com a chave **pública**, gerando um `SealedSecret` — este sim, versionável:

```
secret.yaml ──kubeseal──▶ sealedsecret.yaml ──git──▶ cluster ──controller descriptografa──▶ Secret
   (nunca commitar)         (seguro p/ Git)                        (só o cluster consegue)
```

Simples, autossuficiente, perfeito para times pequenos/GitOps puro. Custos: o segredo "mora" no repositório (rotacionar = re-selar), e a chave do controller vira a joia da coroa (faça backup dela!).

**External Secrets Operator (ESO) — "o Git aponta, o cofre guarda".**
Inverte o modelo: os segredos vivem num **cofre externo** (HashiCorp Vault, AWS Secrets Manager, GCP Secret Manager, Azure Key Vault...) e o Git versiona apenas **referências**:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: { name: db-credentials }
spec:
  refreshInterval: 1h                       # sincronização (rotação semiautomática!)
  secretStoreRef: { name: vault-prod, kind: ClusterSecretStore }
  target: { name: db-credentials }          # o Secret K8s que ele materializa
  data:
  - secretKey: DB_PASSWORD
    remoteRef: { key: loja/prod/db, property: password }
```

O operator (sim, Capítulo 10 de novo) sincroniza cofre → Secret. Ganhos: rotação centralizada, auditoria do cofre, um só lugar para revogar. Custo: uma dependência externa crítica. **É o padrão corporativo dominante.**

**Vault (e afins) com injeção direta** — o passo além: a aplicação (ou um sidecar/CSI driver) busca o segredo do cofre em memória, e o Secret do Kubernetes **nem existe**. Máxima segurança, máxima fricção — para os segredos mais sensíveis.

**Regra de decisão rápida**: time pequeno, tudo em Git → Sealed Secrets; empresa com cofre (ou multi-cluster) → ESO; requisito extremo → injeção direta. Em todos os casos: os três itens de higiene continuam obrigatórios — **as ferramentas alimentam a interface Secret com segurança; não dispensam protegê-la** (a conclusão do Capítulo 5, agora completa).

### 8.3.2 Scan de imagens e supply chain

Última porta: tudo que este curso constrói executa **imagens** — e uma imagem é uma pilha de software de terceiros (Capítulo 1: camadas!). A pergunta de supply chain: *você sabe o que está rodando, de onde veio e o que há de vulnerável dentro?*

**1. Scan de vulnerabilidades — o básico universal.**
Scanners comparam os pacotes das camadas com bancos de CVEs. O **Trivy** é o padrão aberto de fato — experimente agora:

```bash
# Instale o trivy (pacote/brew) e:
trivy image nginx:1.27
# ...lista de CVEs por severidade (CRITICAL/HIGH/...), pacote e versão corrigida
trivy image --severity CRITICAL,HIGH --exit-code 1 loja/api:2.4.1
#            ↑ o modo CI: falha o pipeline se houver crítico — o portão de qualidade
```

Onde escanear (defesa em camadas, de novo): no **build/CI** (barato, cedo), no **registry** (Harbor e os registries de nuvem escaneiam continuamente — pega CVEs *descobertas depois* do build) e/ou no **admission** do cluster (o portão final).

**2. Reduza a superfície antes de escanear** — a vulnerabilidade que não existe não precisa de patch:

- **Imagens mínimas**: `alpine`, **distroless** (só o app e runtime — sem shell!) ou `scratch` (Go estático). Menos pacotes = menos CVEs = scans limpos de verdade. Bônus de segurança: sem shell, `kubectl exec` do invasor não tem onde correr.
- **Multi-stage builds**: compile no estágio gordo, copie só o artefato para o estágio final. Compiladores e ferramentas de build não vão para produção.
- **Tags imutáveis / digests** (Capítulo 5): `latest` em produção é não saber o que roda — e o que não se sabe, não se audita. Fixe versão; ideal, o digest `@sha256:...`.
- **`imagePullPolicy` coerente** e registries **privados e restritos** (com `imagePullSecrets` — Capítulo 5): política de admissão (Kyverno/Gatekeeper, 8.2.1) proibindo registries desconhecidos fecha o cerco.

**3. Procedência: assinatura e SBOM (o mapa do avançado).**

- **Assinatura de imagens** com **cosign** (projeto Sigstore): o CI assina o que constrói; um admission controller no cluster **só admite imagens assinadas pela sua chave**. Elimina a classe inteira de ataque "imagem trocada no registry".
- **SBOM** (Software Bill of Materials): o inventário formal do que existe dentro da imagem (`trivy image --format cyclonedx ...` gera um). Quando a próxima Log4Shell estourar, quem tem SBOMs responde "onde estou vulnerável?" em minutos, não semanas.
- Frameworks que amarram tudo (SLSA, políticas de proveniência): fica a referência para o pós-curso.

**O pipeline seguro, de ponta a ponta (síntese do capítulo no fluxo de build):**

```
código ─▶ build multi-stage (imagem distroless, USER não-root)
       ─▶ trivy scan (falha se CRITICAL) ─▶ cosign sign ─▶ push (registry privado)
       ─▶ deploy: admission verifica assinatura + PSS restricted + policies Kyverno
       ─▶ runtime: RBAC mínimo, SecurityContext duro, NetworkPolicies default-deny
```

**Exercício de fixação 8.3**
1. Conecte três pontas: por que encryption at rest no etcd, o backup do 6.4.3 e a gestão de secrets formam um só problema?
2. Sua empresa quer GitOps completo e já usa AWS Secrets Manager. Sealed Secrets ou ESO? Justifique com dois critérios e cite o que NÃO muda na higiene básica.
3. Um scan da sua imagem `python:3.12` (completa) lista 200 CVEs; o app usa 5 bibliotecas. Proponha duas mudanças de build que reduzam drasticamente a lista e explique por que "sem shell" também é feature de segurança.
4. Explique como assinatura com cosign + admission controller impede o ataque "alguém com acesso ao registry substituiu a tag 2.4.1". Por que fixar o digest também mitigaria — e qual a vantagem da assinatura sobre o digest?
5. Desenhe (texto ou diagrama) o seu pipeline seguro para a API do projeto final, marcando em que ponto cada seção deste capítulo atua.

---

## Laboratório consolidado do capítulo

No cluster do Capítulo 6 (Calico!) — ~50 min:

```bash
kubectl create namespace lab8
kubectl label namespace lab8 pod-security.kubernetes.io/warn=restricted

# 1. A SA sem poderes (e com poderes)
kubectl create serviceaccount leitor -n lab8
kubectl create role le-pods --verb=get,list --resource=pods -n lab8
kubectl create rolebinding leitor-le --role=le-pods --serviceaccount=lab8:leitor -n lab8
kubectl auth can-i list pods -n lab8 --as=system:serviceaccount:lab8:leitor      # yes
kubectl auth can-i delete pods -n lab8 --as=system:serviceaccount:lab8:leitor    # no
kubectl auth can-i list secrets -n lab8 --as=system:serviceaccount:lab8:leitor   # no

# 2. O aviso do PSS (modo warn ensinando)
kubectl run ingenuo --image=nginx:1.27 -n lab8
# Warning: would violate PodSecurity "restricted": ... (leia! é o checklist do endurecimento)

# 3. O Pod endurecido que passa limpo
#    (monte o manifesto da seção 8.2.1 — runAsNonRoot exige imagem não-root;
#     use nginxinc/nginx-unprivileged:1.27 e um emptyDir em /tmp)
kubectl apply -f endurecida.yaml -n lab8      # sem warnings
# Suba o enforce e prove que o ingênuo agora é REJEITADO:
kubectl label namespace lab8 pod-security.kubernetes.io/enforce=restricted --overwrite
kubectl delete pod ingenuo -n lab8 && kubectl run ingenuo --image=nginx:1.27 -n lab8   # Error!

# 4. Default-deny e a reabertura consciente
kubectl create deploy api --image=nginxinc/nginx-unprivileged:1.27 -n lab8
kubectl expose deploy api --port=8080 -n lab8
kubectl run teste --rm -it --image=busybox:1.36 -n lab8 -- wget -qO- -T 2 http://api:8080  # funciona
# aplique o default-deny (8.2.2) e repita: TIMEOUT.
# escreva a policy de ingress liberando só Pods com label acesso=sim e comprove os dois lados:
kubectl run negado  --rm -it --image=busybox:1.36 -n lab8 -- wget -qO- -T 2 http://api:8080          # falha
kubectl run aceito --rm -it --labels=acesso=sim --image=busybox:1.36 -n lab8 -- wget -qO- -T 2 http://api:8080  # passa

# 5. A pegadinha do DNS, vivida
#    adicione Egress ao default-deny, veja o nslookup morrer, e conserte com a regra do kube-dns (8.2.2)

# 6. Scan de imagem (na sua estação)
trivy image nginx:1.27 | head -30
trivy image nginxinc/nginx-unprivileged:1.27-alpine | head -30    # compare o tamanho da lista

# 7. Limpeza
kubectl delete namespace lab8
```

---

## Resumo do capítulo

- Toda requisição atravessa **autenticação → autorização → admission**. Humanos vêm de fora (certs/OIDC); workloads usam **ServiceAccounts** — uma por app, token projetado, `automount: false` quando não precisar da API.
- **RBAC**: Roles/ClusterRoles (recursos × verbos, sub-recursos contam!) ligadas por bindings a users/groups/SAs. Allow-only, menor privilégio, grupos nos bindings, ClusterRole+RoleBinding como padrão-ouro, `auth can-i` como ferramenta diária — e atenção às escaladas indiretas (`pods/exec`, criar Pods com SAs alheias).
- **SecurityContext** endurece o processo (runAsNonRoot, drop ALL, readOnlyRootFilesystem, seccomp); **Pod Security Standards** impõem isso por namespace (baseline/restricted × warn/audit/enforce) com migração gradual.
- **NetworkPolicies** (aplicadas pelo CNI — Calico/Cilium, não Flannel): default-deny primeiro, aberturas explícitas depois; lembre o DNS no egress; domine o E/OU dos seletores; teste sempre.
- Secrets em escala: higiene primeiro (encryption at rest — inclusive nos backups! —, RBAC, volume>env), depois **Sealed Secrets** (cripto para o Git) ou **External Secrets** (cofre externo, padrão corporativo) — alimentando, nunca substituindo, a interface Secret.
- Supply chain: **scan** (Trivy no CI/registry/admission), **superfície mínima** (distroless, multi-stage, digests), **procedência** (cosign, SBOM) — culminando no pipeline seguro de ponta a ponta.

**Ponte para o Capítulo 9**: o cluster está trancado — mas segurança sem visibilidade é fé. Como saber o que está acontecendo lá dentro? Quando o Pod entrar em CrashLoopBackOff às 3h, quais serão seus instrumentos? Logs, métricas, Prometheus, Grafana e o método de troubleshooting são o próximo capítulo.
