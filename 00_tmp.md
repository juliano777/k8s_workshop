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
kubectl create deployment nginx2 --image=nginx
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




kubectl expose deployment deploy-www --name=svc-www --type=LoadBalancer --port=9000


kubectl expose deployment deploy-www --name=svc-www --type=NodePort --port=9000

kubectl expose deployment deploy-www --name=svc-www --port=80 --target-port=9000
