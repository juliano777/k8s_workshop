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
#
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
#
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
#
kubectl rollout undo ds ds01 --to-revision=1
```

```bash
#
kubectl rollout status ds ds01
```


```bash
#
kubectl delete -f ds_01.yaml
```


```bash
#
vim ds_01.yaml
```

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ds01
spec:
  template:
    metadata:
      labels:
        system: DaemonOne
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
  updateStrategy:
    type: RollingUpdate
```

```bash
#
kubectl create -f ds_01.yaml
```

```bash
#
kubectl get daemonset
```

```bash
#
kubectl describe ds ds01
```

```bash
#
kubectl get ds ds01 -o yaml | grep -A 2 Strategy
```

```bash
#
kubectl set image ds ds01 nginx=nginx:latest
```

```bash
#
kubectl get daemonset
```

```bash
#
kubectl get pods -o wide
```

```bash
#
kubectl describe ds ds01
```

```bash
#
kubectl rollout history ds ds01
```

```bash
#
kubectl rollout history ds ds01 --revision=1
```

```bash
#
kubectl rollout history ds ds01 --revision=2
```

```bash
#
kubectl rollout undo ds ds01 --to-revision=1
```

```bash
#
kubectl rollout status ds ds01
```

```bash
#
kubectl delete ds ds01
```