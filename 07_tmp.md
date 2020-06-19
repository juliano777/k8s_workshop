# 


```bash
# Listando histórico de mudanças do DaemonSet:
kubectl rollout history ds ds01
```

<pre><i>
daemonset.apps/ds01 
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
</i></pre>



```bash
# Detalhes da revisão 1:
kubectl rollout history ds ds01 --revision=1
```

<pre><i>
daemonset.apps/ds01 with revision #1
Pod Template:
  Labels:	system=HeavyMetal
  Containers:
   www:
    Image:	nginx:alpine
    Port:	80/TCP
    Host Port:	0/TCP
    Environment:	<none>
    Mounts:	<none>
  Volumes:	<none>
</i></pre>



```bash
# Detalhes da revisão 2:
kubectl rollout history ds ds01 --revision=2
```

<pre><i>
daemonset.apps/ds01 with revision #2
Pod Template:
  Labels:	system=HeavyMetal
  Containers:
   www:
    Image:	nginx:latest
    Port:	80/TCP
    Host Port:	0/TCP
    Environment:	<none>
    Mounts:	<none>
  Volumes:	<none>
</i></pre>



```bash
# Voltando para a revisão 1:
kubectl rollout undo ds ds01 --to-revision=1
```



```bash
# Verificando o status do rollout:
kubectl rollout status ds ds01
```

<pre><i>
daemon set "ds01" successfully rolled out
</i></pre>



```bash
# Removendo o DaemonSet pelo YAML:
kubectl delete -f ds_01.yaml
```


```bash
# Novo conteúdo para o DaemonSet que será recriado:
vim ds_01.yaml
```

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ds01
spec:
  selector:
    matchLabels:
      system: HeavyMetal
  template:
    metadata:
      labels:
        system: HeavyMetal
    spec:
      containers:
      - name: www
        image: nginx:alpine
        ports:
        - containerPort: 80
  updateStrategy:
    type: OnDelete
```

```bash
# Aplicando o YAML:
kubectl apply -f ds_01.yaml
```

```bash
# Listar os pods rodando:
kubectl get pods -l system=HeavyMetal
```

<pre><i>
NAME         READY   STATUS    RESTARTS   AGE
ds01-lnjzh   1/1     Running   0          23s
ds01-xmtvr   1/1     Running   0          23s
</i></pre>



```bash
# Verificando a estratégia de update (updateStrategy):
kubectl get ds ds01 -o yaml | fgrep -A 2 ' updateStrategy' | fgrep type
```

<pre><i>
    type: OnDelete
</i></pre>

Isso significa que para aplicar qualquer atualização é preciso que cada pod seja apagado para então os que forem criados no lugar estejam com as atualizações.