```bash
# Exibe os nós do cluster:
kubectl get nodes
```



```bash
# Descrição do nó k8s-02:
kubectl describe node k8s-02
```



```bash
# Criação de um pod:
kubectl run nginx --image=nginx
```



```bash
# Listando pods:
kubectl get pods
```
<pre><i>
NAME    READY   STATUS    RESTARTS   AGE
nginx   1/1     Running   0          2m44s
</i></pre>



**Service** &rarr; **Deployment** &rarr; **ReplicaSet** &rarr; **Pod**



```bash
# Criação de um deployment:
kubectl create deployment nginx2 --image=nginx
```



```bash
# Listando deployments:
kubectl get deployments
```
<pre><i>
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
nginx2   1/1     1            1           49s
</i></pre>



```bash
# Listando replicasets:
kubectl get replicasets
```
<pre><i>
NAME                DESIRED   CURRENT   READY   AGE
nginx2-669c86457c   1         1         1       90s
</i></pre>




```bash
# Listando pods:
kubectl get pods
```
<pre><i>
NAME                      READY   STATUS    RESTARTS   AGE
nginx                     1/1     Running   2          127m
nginx2-669c86457c-j4ff7   1/1     Running   2          123m
</i></pre>



```bash
# Quem controla o pod?:
kubectl describe pods nginx2-669c86457c-j4ff7 | fgrep 'Controlled By'
```
<pre><i>
Controlled By:  ReplicaSet/nginx2-669c86457c
</i></pre>



```bash
# Quem controla o replicaset?:
kubectl describe replicasets nginx2-669c86457c | fgrep 'Controlled By'
```
<pre><i>
Controlled By:  Deployment/nginx2
</i></pre>



```bash
# Remover o deployment e toda sua estrutura subjascente:
kubectl delete deployments.apps nginx2
```



```bash
# Remover todos os pods:
kubectl delete pods --all
```



```bash
# Remover todos os pods:
kubectl delete pods --all
```



```bash
# Criação de um deployment:
kubectl create deployment deploy-www --image=nginx
```



```bash
# Fazendo a escala do deployment para 10 réplicas:
kubectl scale --replicas=10 deployment deploy-www
```



```bash
# Checando pods:
kubectl get pods
```
<pre><i>
NAME                          READY   STATUS    RESTARTS   AGE
deploy-www-7df7f685b8-56hwn   1/1     Running   0          31m
deploy-www-7df7f685b8-6smwk   1/1     Running   0          2m
deploy-www-7df7f685b8-fdnh5   1/1     Running   0          2m
deploy-www-7df7f685b8-fkspg   1/1     Running   0          2m
deploy-www-7df7f685b8-fn4k7   1/1     Running   0          2m
deploy-www-7df7f685b8-fx6l2   1/1     Running   0          2m
deploy-www-7df7f685b8-g2krq   1/1     Running   0          2m
deploy-www-7df7f685b8-pxqt6   1/1     Running   0          2m
deploy-www-7df7f685b8-vzhrd   1/1     Running   0          2m
deploy-www-7df7f685b8-zq7mq   1/1     Running   0          2m
</i></pre>



```bash
# Fazendo a escala do deployment para 5 réplicas:
kubectl scale --replicas=5 deployment deploy-www
```



```bash
# Checando pods:
kubectl get pods
```
<pre><i>
NAME                          READY   STATUS    RESTARTS   AGE
deploy-www-7df7f685b8-56hwn   1/1     Running   0          33m
deploy-www-7df7f685b8-fkspg   1/1     Running   0          3m47s
deploy-www-7df7f685b8-fn4k7   1/1     Running   0          3m47s
deploy-www-7df7f685b8-fx6l2   1/1     Running   0          3m47s
deploy-www-7df7f685b8-vzhrd   1/1     Running   0          3m47s
</i></pre>



kubectl get deployments deploy-www -o yaml > www.yaml

kubectl expose deployment deploy-www --type=NodePort --port=80 --name=svc-www


kubectl expose deployment deploy-www --type=NodePort --port=80 --name=svc-www


kubectl expose deployment deploy-www --name=svc-www --port=80 --target-port=8080 --protocol=TCP --type=ClusterIP --labels=app=teste,setor=teste


kubectl get service svc-www 
NAME      TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
svc-www   NodePort   10.107.44.106   <none>        80:31651/TCP   8s



# Tipos de Serviços

Um serviço Kubernetes é uma abstração que define um conjunto lógico de pods e uma política de acesso.<br />
Serviços podem ser expostos de maneiras diferentes especificando o tipo (`type`) na especificação (`spec`) do serviço.<br />
Cada tipo define a acessibilidade dentro e fora do cluster.

- ClusterIP;
- NodePort;
- LoadBalancer.


## ClusterIP

Expoe um serviço em um IP interno no cluster, que faz o serviço apenas ser alcançável apenas dentro do cluster.<br />
É o tipo de serviço padrão caso `type` não for especificado.


```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: deploy-wwww
spec:
  selector:
    matchLabels:
      app: nginx-app
  replicas: 10
  template:
    metadata:
      labels:
        app: nginx-app
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: nginx-app
  name: svc-www
  namespace: default
spec:
  type: ClusterIP  # Definição do tipo de service
  ports:
    - port: 80
  selector:
    app: nginx-app
```

```bash
# Aplique o arquivo YAML com o comando:
kubectl apply -f <arquivo YAML>
```


```bash
# Verifique o serviço:
kubectl get service svc-www
```

<pre><i>
NAME      TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
svc-www   ClusterIP   10.102.220.246   <none>        80/TCP    2m21s
</i></pre>


kubectl get pods


kubectl exec -it deploy-wwww-5b7df844dd-x9lnk  curl 10.102.220.246:80



## NodePort

É um serviço ClusterIP com uma capacidade adicional: é alcançável pelo endereço IP do nó bem como pelo IP do cluster atribuído.<br />
A maneira como isso é feita e bem direta, pois, quando o Kubernetes cria um serviço NodePort, aloca uma porta na faixa entre 30000 a 32767
e abre essa porta em todos os nós (por isso o nome NodePort). Conexões a essa porta são redirecionadas para o IP do cluster.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: deploy-wwww
spec:
  selector:
    matchLabels:
      app: nginx-app
  replicas: 10
  template:
    metadata:
      labels:
        app: nginx-app
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: nginx-app
  name: svc-www
  namespace: default
spec:
  type: NodePort  # Definição do tipo de service
  ports:
    - port: 80
  selector:
    app: nginx-app
```

```bash
# Aplique o arquivo YAML com o comando:
kubectl apply -f <arquivo YAML>
```


```bash
# Verificando informações do service:
kubectl get service svc-www
```
<pre><i>
NAME      TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
svc-www   NodePort   10.99.152.115   <none>        80:30430/TCP   1m01s
</i></pre>

* IP do Cluster: 10.99.152.115
* Porta do nó (NodePort): 30430

Podemos também definir NodePort.



```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: deploy-wwww
spec:
  selector:
    matchLabels:
      app: nginx-app
  replicas: 10
  template:
    metadata:
      labels:
        app: nginx-app
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: nginx-app
  name: svc-www
  namespace: default
spec:
  type: NodePort  # Definição do tipo de service
  ports:
    - port: 80
      nodePort: 30777  # NodePort
      protocol: TCP
  selector:
    app: nginx-app
```

```bash
# Aplique o arquivo YAML com o comando:
kubectl apply -f <arquivo YAML>
```



```bash
# Verificando informações do service:
kubectl get service svc-www
```
<pre><i>
NAME      TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
svc-www   NodePort   10.99.152.115   <none>        80:30777/TCP   16h
</i></pre>

* IP do Cluster: 10.99.152.115
* Porta do nó (NodePort): 30777






## LoadBalancer
NodePort=X