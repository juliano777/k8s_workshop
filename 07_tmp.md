# 


```bash
#
kubectl rollout history ds daemon-set-primeiro
```

```bash
#
kubectl rollout history ds daemon-set-primeiro --revision=1
```

```bash
#
kubectl rollout history ds daemon-set-primeiro --revision=2
```

```bash
#
kubectl rollout undo ds daemon-set-primeiro --to-revision=1
```

```bash
#
kubectl rollout status ds daemon-set-primeiro
```

```bash
#
kubectl describe daemon-set-primeiro-hp4qc | fgrep -i image
```

```bash
#
kubectl delete -f primeiro-daemonset.yaml
```


```bash
#
vim primeiro-daemonset.yaml
```

```yaml
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: daemon-set-primeiro
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
kubectl create -f primeiro-daemonset.yaml
```

```bash
#
kubectl get daemonset
```

```bash
#
kubectl describe ds daemon-set-primeiro
```

```bash
#
kubectl get ds daemon-set-primeiro -o yaml | grep -A 2 Strategy
```

```bash
#
kubectl set image ds daemon-set-primeiro nginx=nginx:1.15.0
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
kubectl describe ds daemon-set-primeiro
```

```bash
#
kubectl rollout history ds daemon-set-primeiro
```

```bash
#
kubectl rollout history ds daemon-set-primeiro --revision=1
```

```bash
#
kubectl rollout history ds daemon-set-primeiro --revision=2
```

```bash
#
kubectl rollout undo ds daemon-set-primeiro --to-revision=1
```

```bash
#
kubectl rollout status ds daemon-set-primeiro
```

```bash
#
kubectl delete ds daemon-set-primeiro
```