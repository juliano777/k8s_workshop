# Deployments

Um deployment fornece atualizações declarativas para Pods e ReplicaSets.

Descreve-se um estado desejado em um Deployment e o Controller do Deployment muda o atual estado para o estado desejado a uma taxa controlada.

Um Deployment pode ser definido para criar novos ReplicaSets ou remover Deployments existentes e adotar todos seus recursos com novos Deployments.



```bash
# Criação do YAML do deployment:
vim deploy_01.yaml
```


```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    run: nginx
    app: heavymetal
  name: deploy01
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      run: nginx
  template:
    metadata:
      labels:
        run: nginx
        color: Green
    spec:
      containers:
      - image: nginx
        imagePullPolicy: Always
        name: nginx2
        ports:
        - containerPort: 80
          protocol: TCP
        resources: {}
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      schedulerName: default-scheduler
      securityContext: {}
      terminationGracePeriodSeconds: 30
```



```bash
# Aplicando o YAML:
kubectl apply -f deploy_01.yaml
```



```bash
# Criação do YAML do segundo deployment:
vim deploy_02.yaml
```


```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    run: nginx
  name: deploy02
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      run: nginx
  template:
    metadata:
      labels:
        run: nginx
        color: Orange
    spec:
      containers:
      - image: nginx
        imagePullPolicy: Always
        name: nginx2
        ports:
        - containerPort: 80
          protocol: TCP
        resources: {}
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      schedulerName: default-scheduler
      securityContext: {}
      terminationGracePeriodSeconds: 30
```



```bash
# Aplicando o YAML:
kubectl apply -f deploy_02.yaml
```



```bash
# Listando deployments:
kubectl get deployments
```

<pre><i>
NAME       READY   UP-TO-DATE   AVAILABLE   AGE
deploy01   1/1     1            1           7m23s
deploy02   1/1     1            1           60s
</i></pre>



```bash
# Listando pods:
kubectl get pods
```

<pre><i>
NAME                        READY   STATUS    RESTARTS   AGE
deploy01-5fd6dcb8d8-tkvq9   1/1     Running   0          9m48s
deploy02-5dc8f99fdf-s6p8s   1/1     Running   0          3m25s
</i></pre>



```bash
# Descrição de um dos pods:
kubectl describe pod deploy01-5fd6dcb8d8-tkvq9
```

<pre><i>
Name:         deploy01-5fd6dcb8d8-tkvq9
Namespace:    default
Priority:     0
Node:         k8s-03.local/192.168.56.30
Start Time:   Wed, 17 Jun 2020 09:31:14 -0300
Labels:       color=Green
              pod-template-hash=5fd6dcb8d8
              run=nginx
Annotations:  cni.projectcalico.org/podIP: 172.0.86.131/32
              cni.projectcalico.org/podIPs: 172.0.86.131/32
Status:       Running
IP:           172.0.86.131
IPs:
  IP:           172.0.86.131
Controlled By:  ReplicaSet/deploy01-5fd6dcb8d8
Containers:
  nginx2:
    Container ID:   docker://5cf36f23e08e7086b65896aeecede0d754b623a2083743cc627fb044a8574506
    Image:          nginx
    Image ID:       docker-pullable://nginx@sha256:21f32f6c08406306d822a0e6e8b7dc81f53f336570e852e25fbe1e3e3d0d0133
    Port:           80/TCP
    Host Port:      0/TCP
    State:          Running
      Started:      Wed, 17 Jun 2020 09:31:18 -0300
    Ready:          True
    Restart Count:  0
    Environment:    <none>
    Mounts:
      /var/run/secrets/kubernetes.io/serviceaccount from default-token-fg5r4 (ro)
Conditions:
  Type              Status
  Initialized       True 
  Ready             True 
  ContainersReady   True 
  PodScheduled      True 
Volumes:
  default-token-fg5r4:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  default-token-fg5r4
    Optional:    false
QoS Class:       BestEffort
Node-Selectors:  <none>
Tolerations:     node.kubernetes.io/not-ready:NoExecute for 300s
                 node.kubernetes.io/unreachable:NoExecute for 300s
Events:
  Type    Reason     Age        From                   Message
  ----    ------     ----       ----                   -------
  Normal  Scheduled  <unknown>  default-scheduler      Successfully assigned default/deploy01-5fd6dcb8d8-tkvq9 to k8s-03.local
  Normal  Pulling    12m        kubelet, k8s-03.local  Pulling image "nginx"
  Normal  Pulled     12m        kubelet, k8s-03.local  Successfully pulled image "nginx"
  Normal  Created    12m        kubelet, k8s-03.local  Created container nginx2
  Normal  Started    12m        kubelet, k8s-03.local  Started container nginx2
</i></pre>



```bash
# Descrição de um dos deployments:
kubectl describe deployment deploy01
```

<pre><i>
Name:                   deploy01
Namespace:              default
CreationTimestamp:      Wed, 17 Jun 2020 09:31:14 -0300
Labels:                 app=heavymetal
                        run=nginx
Annotations:            deployment.kubernetes.io/revision: 1
Selector:               run=nginx
Replicas:               1 desired | 1 updated | 1 total | 1 available | 0 unavailable
StrategyType:           RollingUpdate
MinReadySeconds:        0
RollingUpdateStrategy:  25% max unavailable, 25% max surge
Pod Template:
  Labels:  color=Green
           run=nginx
  Containers:
   nginx2:
    Image:        nginx
    Port:         80/TCP
    Host Port:    0/TCP
    Environment:  <none>
    Mounts:       <none>
  Volumes:        <none>
Conditions:
  Type           Status  Reason
  ----           ------  ------
  Available      True    MinimumReplicasAvailable
  Progressing    True    NewReplicaSetAvailable
OldReplicaSets:  <none>
NewReplicaSet:   deploy01-5fd6dcb8d8 (1/1 replicas created)
Events:
  Type    Reason             Age   From                   Message
  ----    ------             ----  ----                   -------
  Normal  ScalingReplicaSet  16m   deployment-controller  Scaled up replica set deploy01-5fd6dcb8d8 to 1
</i></pre>



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



kubectl get pods -l color=Silver
NAME                        READY   STATUS    RESTARTS   AGE
deploy04-8574f6b454-797np   1/1     Running   0          109s
deploy04-8574f6b454-84qpn   1/1     Running   0          109s
deploy04-8574f6b454-pwt4t   1/1     Running   0          109s



kubectl describe pod deploy04-8574f6b454-797np | fgrep image
  Normal  Pulling    2m29s      kubelet, k8s-03.local  Pulling image "nginx:alpine"
  Normal  Pulled     2m6s       kubelet, k8s-03.local  Successfully pulled image "nginx:alpine"



# Edite o deployment mudando a tag da imagem de "alpine" para "latest":
kubectl edit deploy deploy04



# Espere algum tempo e verifique se tem apenas 3 instâncias rodando:
kubectl get pods -l color=Silver

NAME                        READY   STATUS    RESTARTS   AGE
deploy04-67579fc878-dzrcf   1/1     Running   0          28s
deploy04-67579fc878-pfkjl   1/1     Running   0          22s
deploy04-67579fc878-zzw42   1/1     Running   0          17s



# Vamos verificar a imagem que está nos pods tomando um como exemplo:

kubectl describe pod deploy04-67579fc878-dzrcf | fgrep image

  Normal  Pulling    3m18s      kubelet, k8s-02.local  Pulling image "nginx:latest"
  Normal  Pulled     3m14s      kubelet, k8s-02.local  Successfully pulled image "nginx:latest"

Podemos notar que ao editar o deployment, os pods antigos foram encerrados e novos foram criados de acordo com as mudanças.



# Vamos recriar somente o ReplicaSet rs01:
kubectl apply -f rs_01.yaml



# Vamos listar seus pods:
kubectl get pods -l color=Black

NAME         READY   STATUS    RESTARTS   AGE
rs01-6qmvv   1/1     Running   0          29s
rs01-bcb8t   1/1     Running   0          29s
rs01-cnpvr   1/1     Running   0          29s
rs01-k2v2c   1/1     Running   0          29s
rs01-rdff2   1/1     Running   0          29s



# Vamos verificar a imagem usada:
kubectl describe pod rs01-6qmvv | fgrep image

  Normal  Pulling    87s        kubelet, k8s-03.local  Pulling image "nginx"
  Normal  Pulled     84s        kubelet, k8s-03.local  Successfully pulled image "nginx"



# Mude a imagem do ReplicaSet para a tag "alpine"
# (image: nginx:alpine):
kubectl edit rs rs01

Não houve qualquer alteração...


# Apague um pod:
kubectl get pods -l color=Black | fgrep rs01 | awk '{print $1}' | \
head -1 | xargs -i kubectl delete pod {}



# Liste novamente:
kubectl get pods -l color=Black



# Dê um describe no pod mais novo e verifique a imagem:
kubectl get pods -l color=Black | fgrep Running | tail -1 | \
awk '{print $1}' | xargs -i kubectl describe pod {} | fgrep image

  Normal  Pulling    91s        kubelet, k8s-02.local  Pulling image "nginx:alpine"
  Normal  Pulled     84s        kubelet, k8s-02.local  Successfully pulled image "nginx:alpine"

Podemos concluir que ao criarmos um ReplicaSet e o alteramos, tais alterações só terão efeito após "matarmos" seus pods.
Com um deployment é diferente, pois após houver uma alteração, todos os pods são renovados conforme.
