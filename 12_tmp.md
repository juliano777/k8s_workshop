# ConfigMap


ConfigMaps allow you to decouple configuration artifacts from image content to keep containerized applications portable. This page provides a series of usage examples demonstrating how to create ConfigMaps and configure Pods using data stored in ConfigMaps.



```bash
# Criar um diretório para testes:
mkdir /tmp/capitais
```


```bash
# Criar arquivos com conteúdo usando echo:
echo 'São Paulo' > /tmp/capitais/sp
echo 'Rio de Janeiro' > /tmp/capitais/rj
echo 'Belo Horizonte' > /tmp/capitais/mg
echo 'Curitiba' > /tmp/capitais/pr
echo 'Brasília' > br
```


```bash
# 
kubectl create configmap capitais \
  --from-literal rn=Natal \
  --from-file=br \
  --from-file=/tmp/capitais/
```



```bash
# 
kubectl describe configmaps capitais
```

<pre><i>
Name:         capitais
Namespace:    default
Labels:       <none>
Annotations:  <none>

Data
====
pr:
----
Curitiba

rj:
----
Rio de Janeiro

rn:
----
Natal
sp:
----
São Paulo

br:
----
Brasília

mg:
----
Belo Horizonte

Events:  <none>
</i></pre>



```bash
# 
vim pod-capitais.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-capitais
spec:
  containers:
  - image: alpine
    name: alpine-capitais
    command:
      - sleep
      - "3600"
    env:
    - name: foo
      valueFrom:
        configMapKeyRef:
          name: capitais
          key: br
```



```bash
# 
kubectl create -f pod-capitais.yaml
```



```bash
# 
kubectl describe pod pod-capitais | fgrep -A1 Environment
```

<pre><i>
    Environment:
      capitais:  <set to the key 'br' of config map 'capitais'>  Optional: false
</i></pre>



```bash
# 
kubectl exec -it pod-capitais -- sh -c 'set | fgrep foo='
```

<pre><i>
foo='Brasília
</i></pre>



```bash
# Remove o pod:
kubectl delete pod pod-capitais
```



```bash
# 
vim pod-capitais2.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-capitais2
spec:
  containers:
  - image: alpine
    name: alpine-capitais
    command:
      - sleep
      - "3600"
    envFrom:
    - configMapRef:
        name: capitais
```



```bash
# 
kubectl create -f pod-capitais2.yaml
```



```bash
# 
kubectl describe pod pod-capitais2 | fgrep -A1 'Environment Variables from:'
```

<pre><i>
    Environment Variables from:
      capitais    ConfigMap  Optional: false
</i></pre>



```bash
# 
kubectl exec -it pod-capitais2 -- sh -c 'set' | tail -15
```

<pre><i>
PS4='+ '
PWD='/'
SHLVL='1'
TERM='xterm'
br='Brasília
'
mg='Belo Horizonte
'
pr='Curitiba
'
rj='Rio de Janeiro
'
rn='Natal'
sp='São Paulo
'
</i></pre>



```bash
# 
kubectl delete pod pod-capitais2
```



```bash
# 
vim pod-arquivo.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-arquivo
spec:
  containers:
  - image: alpine
    name: alpine-capitais
    command:
      - sleep
      - "3600"
    envFrom:
    - configMapRef:
        name: capitais
```