# 


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
kubectl describe ds01-hp4qc | fgrep -i image
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
        image: nginx:1.7.9
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
kubectl set image ds ds01 nginx=nginx:1.15.0
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