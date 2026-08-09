# ReplicaSet

A ReplicaSet's purpose is to maintain a stable set of replica Pods running at any given time. As such, it is often used to guarantee the availability of a specified number of identical Pods.

## How a ReplicaSet works

A ReplicaSet is defined with fields, including a selector that specifies how to identify Pods it can acquire, a number of replicas indicating how many Pods it should be maintaining, and a pod template specifying the data of new Pods it should create to meet the number of replicas criteria. A ReplicaSet then fulfills its purpose by creating and deleting Pods as needed to reach the desired number. When a ReplicaSet needs to create new Pods, it uses its Pod template.

A ReplicaSet is linked to its Pods via the Pods' metadata.ownerReferences field, which specifies what resource the current object is owned by. All Pods acquired by a ReplicaSet have their owning ReplicaSet's identifying information within their ownerReferences field. It's through this link that the ReplicaSet knows of the state of the Pods it is maintaining and plans accordingly.

A ReplicaSet identifies new Pods to acquire by using its selector. If there is a Pod that has no OwnerReference or the OwnerReference is not a Controller and it matches a ReplicaSet's selector, it will be immediately acquired by said ReplicaSet.

## When to use a ReplicaSet

A ReplicaSet ensures that a specified number of pod replicas are running at any given time. However, a Deployment is a higher-level concept that manages ReplicaSets and provides declarative updates to Pods along with a lot of other useful features. Therefore, we recommend using Deployments instead of directly using ReplicaSets, unless you require custom update orchestration or don't require updates at all.

This actually means that you may never need to manipulate ReplicaSet objects: use a Deployment instead, and define your application in the spec section.



```bash
# YAML de um ReplicaSet:
vim rs_01.yaml
```

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: rs01
  labels:
    app: anyapp
spec:
  replicas: 5
  selector:
    matchLabels:
      color: Black
  template:
    metadata:
      labels:
        color: Black
    spec:
      containers:
      - name: rs01
        image: nginx
        ports:
        - containerPort: 80
```



```bash
# Aplicando o YAML:
kubectl apply -f rs_01.yaml
```



```bash
# Verificando o ReplicaSet criado:
kubectl get rs rs01
```

<pre><i>
NAME   DESIRED   CURRENT   READY   AGE
rs01   5         5         5       3m36s
</i></pre>



```bash
# Descrição do ReplicaSet:
kubectl describe rs rs01
```

<pre><i>
Name:         rs01
Namespace:    default
Selector:     color=Black
Labels:       app=anyapp
Annotations:  Replicas:  5 current / 5 desired
Pods Status:  5 Running / 0 Waiting / 0 Succeeded / 0 Failed
Pod Template:
  Labels:  color=Black
  Containers:
   rs01:
    Image:        nginx
    Port:         80/TCP
    Host Port:    0/TCP
    Environment:  <none>
    Mounts:       <none>
  Volumes:        <none>
Events:
  Type    Reason            Age    From                   Message
  ----    ------            ----   ----                   -------
  Normal  SuccessfulCreate  8m59s  replicaset-controller  Created pod: rs01-g8hpk
  Normal  SuccessfulCreate  8m59s  replicaset-controller  Created pod: rs01-nz7sc
  Normal  SuccessfulCreate  8m59s  replicaset-controller  Created pod: rs01-h4x4d
  Normal  SuccessfulCreate  8m59s  replicaset-controller  Created pod: rs01-gpzzs
  Normal  SuccessfulCreate  8m59s  replicaset-controller  Created pod: rs01-gkd5k
</i></pre>



```bash
# Remover o ReplicaSet:
kubectl delete pod rs01
```



```bash
# Descrição do ReplicaSet:
kubectl get pods -l color=Black
```

<pre><i>
NAME                        READY   STATUS    RESTARTS   AGE
deploy04-7ffdbb84f6-ztkcv   1/1     Running   0          18m
rs01-g8hpk                  1/1     Running   0          14m
rs01-gkd5k                  1/1     Running   0          14m
rs01-gpzzs                  1/1     Running   0          14m
rs01-h4x4d                  1/1     Running   0          14m
rs01-nz7sc                  1/1     Running   0          14m
</i></pre>



```bash
# Apagando o ReplicaSet:
kubectl delete rs rs01
```



```bash
# Verificando os pods que eram controlados pelo ReplicaSet removido:
kubectl get pods -l color=Black
```

Após os pods terminarem desaparecem, pois sem seu controlador devem deixar de existir.



## Alterações: Deployments vs ReplicaSets



```bash
# Criando um novo YAML de deployment:
vim deploy_04.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    run: nginx
    color: Silver
  name: deploy04
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      run: nginx
  template:
    metadata:
      labels:
        run: nginx
        color: Silver
    spec:
      containers:
        - image: nginx:alpine
          imagePullPolicy: Always
          name: deploy04
          ports:
          - containerPort: 80
            protocol: TCP 
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      schedulerName: default-scheduler
```



```bash
# Aplicando o YAML de deployment:
kubectl apply -f deploy_04.yaml
```



```bash
# Listando os pods criados:
kubectl get pods -l color=Silver
```

<pre><i>
NAME                        READY   STATUS    RESTARTS   AGE
deploy04-8574f6b454-797np   1/1     Running   0          109s
deploy04-8574f6b454-84qpn   1/1     Running   0          109s
deploy04-8574f6b454-pwt4t   1/1     Running   0          109s
</i></pre>



```bash
# Pela descrição de um dos pods, verificando a imagem utilizada:
kubectl describe pod deploy04-8574f6b454-797np | fgrep image
```

<pre><i>
  Normal  Pulling    2m29s      kubelet, k8s-03.local  Pulling image "nginx:alpine"
  Normal  Pulled     2m6s       kubelet, k8s-03.local  Successfully pulled image "nginx:alpine"
</i></pre>



```bash
# Edite o deployment mudando a tag da imagem de "alpine" para "latest":
kubectl edit deploy deploy04
```


```bash
# Espere algum tempo e verifique se tem apenas 3 instâncias rodando:
kubectl get pods -l color=Silver
```

<pre><i>
NAME                        READY   STATUS    RESTARTS   AGE
deploy04-67579fc878-dzrcf   1/1     Running   0          28s
deploy04-67579fc878-pfkjl   1/1     Running   0          22s
deploy04-67579fc878-zzw42   1/1     Running   0          17s
</i></pre>



```bash
# Vamos verificar a imagem que está nos pods tomando um como exemplo:
kubectl describe pod deploy04-67579fc878-dzrcf | fgrep image
```

<pre><i>
  Normal  Pulling    3m18s      kubelet, k8s-02.local  Pulling image "nginx:latest"
  Normal  Pulled     3m14s      kubelet, k8s-02.local  Successfully pulled image "nginx:latest"
</i></pre>

Podemos notar que ao editar o deployment, os pods antigos foram encerrados e novos foram criados de acordo com as mudanças.



```bash
# Recriação do ReplicaSet rs01:
kubectl apply -f rs_01.yaml
```


```bash
# Vamos listar seus pods:
kubectl get pods -l color=Black
```

<pre><i>
NAME         READY   STATUS    RESTARTS   AGE
rs01-6qmvv   1/1     Running   0          29s
rs01-bcb8t   1/1     Running   0          29s
rs01-cnpvr   1/1     Running   0          29s
rs01-k2v2c   1/1     Running   0          29s
rs01-rdff2   1/1     Running   0          29s
</i></pre>


```bash
# Vamos verificar a imagem usada:
kubectl describe pod rs01-6qmvv | fgrep image
```

<pre><i>
  Normal  Pulling    87s        kubelet, k8s-03.local  Pulling image "nginx"
  Normal  Pulled     84s        kubelet, k8s-03.local  Successfully pulled image "nginx"
</i></pre>


```bash
# Mude a imagem do ReplicaSet para a tag "alpine"
# (image: nginx:alpine):
kubectl edit rs rs01
```

Não houve qualquer alteração...


```bash
# Apague um pod:
kubectl get pods -l color=Black | fgrep rs01 | awk '{print $1}' | \
head -1 | xargs -i kubectl delete pod {}
```



```bash
# Liste novamente:
kubectl get pods -l color=Black
```



```bash
# Dê um describe no pod mais novo e verifique a imagem:
kubectl get pods -l color=Black | fgrep Running | tail -1 | \
awk '{print $1}' | xargs -i kubectl describe pod {} | fgrep image
```

<pre><i>
  Normal  Pulling    91s        kubelet, k8s-02.local  Pulling image "nginx:alpine"
  Normal  Pulled     84s        kubelet, k8s-02.local  Successfully pulled image "nginx:alpine"
</i></pre>

Podemos concluir que ao criarmos um ReplicaSet e o alteramos, tais alterações só terão efeito após "matarmos" seus pods.
Com um deployment é diferente, pois após houver uma alteração, todos os pods são renovados conforme.