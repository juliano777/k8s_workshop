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



```bash
# :
```


