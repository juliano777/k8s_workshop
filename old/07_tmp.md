# kubectl rollout e updateStrategy


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



```bash
# Mudano a imagem do DaemonSet via linha de comando:
kubectl set image ds ds01 www=nginx:latest
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

São os mesmos pods rodando ainda...



```bash
# Remover o primeiro pod:
kubectl get pods -l system=HeavyMetal | fgrep Running | \
awk '{print $1}' | head -1 | xargs -i kubectl delete pod {}
```

<pre><i>
pod "ds01-lnjzh" deleted
</i></pre>



```bash
# Listar os pods rodando:
kubectl get pods -l system=HeavyMetal
```

<pre><i>
NAME         READY   STATUS    RESTARTS   AGE
ds01-qjstx   1/1     Running   0          99s
ds01-xmtvr   1/1     Running   0          26m
</i></pre>

O primeiro pod mudou...



```bash
# Verificando a imagem do primeiro pod:
kubectl describe pod ds01-qjstx | fgrep 'Image:'
```

<pre><i>
    Image:          nginx:latest
</i></pre>

Esse pod foi o que entrou no lugar do que foi removido, a alteração feita no DaemonSet já consta nele.



```bash
# Verificando a imagem do segundo pod:
kubectl describe pod ds01-xmtvr | fgrep 'Image:'
```

<pre><i>
    Image:          nginx:alpine
</i></pre>

Aqui vemos no pod pré existente que a imagem original continua.




```bash
# Agora vamos mudar o YAML com updateStrategy do tipo RollingUpdate:
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
    rollingUpdate:
      maxUnavailable: 1
    type: RollingUpdate
```



```bash
# Aplicar o YAML:
kubectl apply -f ds_01.yaml
```



```bash
# Verificando a estratégia de update (updateStrategy):
kubectl get ds ds01 -o yaml | fgrep -A 3 ' updateStrategy' | fgrep type
```

<pre><i>
    type: RollingUpdate
</i></pre>



```bash
# Listar os pods rodando:
kubectl get pods -l system=HeavyMetal
```

<pre><i>
NAME         READY   STATUS    RESTARTS   AGE
ds01-2tp58   1/1     Running   0          27s
ds01-lkcsh   1/1     Running   0          27s
</i></pre>



```bash
# Mudano a imagem do DaemonSet via linha de comando:
kubectl set image ds ds01 www=nginx:latest
```


```bash
# Após algum tempo, listar os pods rodando após a mudança:
kubectl get pods -l system=HeavyMetal
```

<pre><i>
NAME         READY   STATUS    RESTARTS   AGE
ds01-jnvkz   1/1     Running   0          12s
ds01-zqz9x   1/1     Running   0          4s
</i></pre>

Com updateStrategy RollingUpdate a mudança foi aplicada imediatamente, fazendo com que os pods fossem renovados conforme.