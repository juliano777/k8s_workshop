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

