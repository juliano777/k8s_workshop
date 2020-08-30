# RBAC

_Role-Based Access Control_, em português; Controle de ACeso Baseado em Papel (Função) é um método de regular o acesso a recursos ou rede com base nas funções de usuários individuais.
A autorização RBAC usa o grupo de API rbac.authorization.k8s.io para conduzir as decisões de autorização, permitindo dinamicamente configurar políticas através da API do Kubernetes.

https://kubernetes.io/docs/reference/access-authn-authz/rbac/




```bash
# Cópia do diretório template de home de usuário padrão para /tmp:
sudo cp -r /etc/skel /tmp/
```



```bash
# Cópia do diretório .kube para /tmp/skel:
sudo cp -r ~/.kube /tmp/skel/
```



```bash
# Criação de grupos:
sudo groupadd alpha
sudo groupadd beta
```



```bash
# Criação de usuários:
sudo useradd -g alpha -k /tmp/skel -d /home/vivaldi -s /bin/bash -m vivaldi
sudo useradd -g alpha -k /tmp/skel -d /home/bach -s /bin/bash -m bach
sudo useradd -g alpha -k /tmp/skel -d /home/beethoven -s /bin/bash \
  -m beethoven
sudo useradd -g beta -k /tmp/skel -d /home/gauss -s /bin/bash -m gauss
sudo useradd -g beta -k /tmp/skel -d /home/euler -s /bin/bash -m euler
```



```bash
# Verificando se o RBAC está ativado no cluster:
kubectl -n kube-system describe pod -l component=kube-apiserver | \
  fgrep 'authorization-mode'
```

<pre><i>
--authorization-mode=Node,RBAC
</i></pre>



```bash
# Criação de uma conta:
kubectl create serviceaccount vivaldi
```



```bash
# Verificando contas:
kubectl get serviceaccounts 
```

<pre><i>
NAME      SECRETS   AGE
default   1         72d
vivaldi   1         7s
</i></pre>



```bash
# Descrição da conta criada:
kubectl describe serviceaccounts vivaldi
```

<pre><i>
Name:                vivaldi
Namespace:           default
Labels:              <none>
Annotations:         <none>
Image pull secrets:  <none>
Mountable secrets:   vivaldi-token-5hnz7
Tokens:              vivaldi-token-5hnz7
Events:              <none>
</i></pre>



```bash
# Verificando cluster roles:
kubectl get clusterroles | head
```

<pre><i>
NAME                                                                   CREATED AT
admin                                                                  2020-06-04T19:49:30Z
calico-kube-controllers                                                2020-06-04T19:50:14Z
calico-node                                                            2020-06-04T19:50:14Z
cluster-admin                                                          2020-06-04T19:49:30Z
edit                                                                   2020-06-04T19:49:30Z
kubeadm:get-nodes                                                      2020-06-04T19:49:32Z
system:aggregate-to-admin                                              2020-06-04T19:49:30Z
system:aggregate-to-edit                                               2020-06-04T19:49:30Z
system:aggregate-to-view                                               2020-06-04T19:49:30Z
</i></pre>



```bash
# 
kubectl describe clusterrole cluster-admin
```

<pre><i>
Name:         cluster-admin
Labels:       kubernetes.io/bootstrapping=rbac-defaults
Annotations:  rbac.authorization.kubernetes.io/autoupdate: true
PolicyRule:
  Resources  Non-Resource URLs  Resource Names  Verbs
  ---------  -----------------  --------------  -----
  *.*        []                 []              [*]
             [*]                []              [*]
</i></pre>



```bash
# 
kubectl describe clusterrole view | head -20
```

<pre><i>
Name:         view
Labels:       kubernetes.io/bootstrapping=rbac-defaults
              rbac.authorization.k8s.io/aggregate-to-edit=true
Annotations:  rbac.authorization.kubernetes.io/autoupdate: true
PolicyRule:
  Resources                                    Non-Resource URLs  Resource Names  Verbs
  ---------                                    -----------------  --------------  -----
  bindings                                     []                 []              [get list watch]
  configmaps                                   []                 []              [get list watch]
  endpoints                                    []                 []              [get list watch]
  events                                       []                 []              [get list watch]
  limitranges                                  []                 []              [get list watch]
  namespaces/status                            []                 []              [get list watch]
  namespaces                                   []                 []              [get list watch]
  persistentvolumeclaims/status                []                 []              [get list watch]
  persistentvolumeclaims                       []                 []              [get list watch]
  pods/log                                     []                 []              [get list watch]
  pods/status                                  []                 []              [get list watch]
  pods                                         []                 []              [get list watch]
  replicationcontrollers/scale                 []                 []              [get list watch]
</i></pre>



```bash
# 
kubectl describe clusterrolebinding cluster-admin
```

<pre><i>
Name:         cluster-admin
Labels:       kubernetes.io/bootstrapping=rbac-defaults
Annotations:  rbac.authorization.kubernetes.io/autoupdate: true
Role:
  Kind:  ClusterRole
  Name:  cluster-admin
Subjects:
  Kind   Name            Namespace
  ----   ----            ---------
  Group  system:masters
</i></pre>



```bash
# 
kubectl create clusterrolebinding foo --serviceaccount=default:vivaldi --clusterrole=cluster-admin
```



```bash
# 
kubectl describe clusterrolebinding foo
```

<pre><i>
Name:         foo
Labels:       <none>
Annotations:  <none>
Role:
  Kind:  ClusterRole
  Name:  cluster-admin
Subjects:
  Kind            Name     Namespace
  ----            ----     ---------
  ServiceAccount  vivaldi  default
</i></pre>



```bash
# 
vim admin-user.yaml
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system  # Namespace de administração do k8s
```



```bash
# 
kubectl apply -f admin-user.yaml
```



```bash
# 
kubectl -n kube-system get serviceaccount | head
```

<pre><i>
NAME                                 SECRETS   AGE
admin-user                           1         2m11s
attachdetach-controller              1         72d
bootstrap-signer                     1         72d
calico-kube-controllers              1         72d
calico-node                          1         72d
certificate-controller               1         72d
clusterrole-aggregation-controller   1         72d
coredns                              1         72d
cronjob-controller                   1         72d
</i></pre>



```bash
# 
vim admin-cluster-role-binding.yaml
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kube-system
```



```bash
# 
kubectl apply -f admin-cluster-role-binding.yaml
```



```bash
# 
kubectl -n kube-system describe clusterrolebinding admin-user
```

<pre><i>
Name:         admin-user
Labels:       <none>
Annotations:  Role:
  Kind:       ClusterRole
  Name:       cluster-admin
Subjects:
  Kind            Name        Namespace
  ----            ----        ---------
  ServiceAccount  admin-user  kube-system
</i></pre>