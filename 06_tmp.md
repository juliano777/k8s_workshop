# DaemonSet

Deleting a DaemonSet will clean up the Pods it created.

Some typical uses of a DaemonSet are:

    running a cluster storage daemon on every node
    running a logs collection daemon on every node
    running a node monitoring daemon on every node

In a simple case, one DaemonSet, covering all nodes, would be used for each type of daemon. A more complex setup might use multiple DaemonSets for a single type of daemon, but with different flags and/or different memory and cpu requests for different hardware types.


Um DaemonSet assegura que todos ou (ou alguns) nós rodem uma cópia de um pod.
À medida que os nós são adicionados ao cluster, os Pods são adicionados a eles.
E à medida que os nós são removidos do cluster, esses pods são eliminados pelo garbage collector.
Apagando um DaemonSet vai limpar os pods criados por ele.

```bash
# Editar o arquivo YAML de criação do DaemonSet:
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
# Listando DaemonSets:
kubectl get ds
```

<pre><i>
NAME   DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
ds01   2         2         2       2            2           <none>          6m22s
</i></pre>



```bash
# Onde estão rodando seus pods?:
kubectl get pods -l system=HeavyMetal -o wide
```

<pre><i>
NAME         READY   STATUS    RESTARTS   AGE   IP             NODE           NOMINATED NODE   READINESS GATES
ds01-s4k8g   1/1     Running   0          20m   172.0.131.28   k8s-02.local   <none>           <none>
ds01-sj62z   1/1     Running   0          20m   172.0.86.163   k8s-03.local   <none>           <none>
</i></pre>

Rodando em apenas dois nós?


```bash
# Listando os nós do cluster:
kubectl get nodes
```

<pre><i>
NAME           STATUS   ROLES    AGE   VERSION
k8s-01         Ready    master   47h   v1.18.3
k8s-02.local   Ready    <none>   47h   v1.18.3
k8s-03.local   Ready    <none>   47h   v1.18.3
</i></pre>

Mas temos 3 (três) nós no cluster...



```bash
# Checando taints no nó master:
kubectl describe nodes k8s-01 | fgrep Taints
```

<pre><i>
Taints:             node-role.kubernetes.io/master:NoSchedule
</i></pre>

Eis a explicação, o nó master é tainted com NoSchedule.
Ou seja, nenhum novo pod será criado nesse nó.



```bash
# Mudano a imagem do DaemonSet via linha de comando:
kubectl set image ds ds01 www=nginx:latest
```



```bash
# Verificando a imagem do DaemonSet:
kubectl describe ds ds01 | fgrep Image
```

<pre><i>
    Image:        nginx:latest
</i></pre>


Assim que houve a atualização todos os atuais pods foram terminados.
Novos pods foram criados com a modificação feita.