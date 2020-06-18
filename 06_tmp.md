# DaemonSet

A DaemonSet ensures that all (or some) Nodes run a copy of a Pod. As nodes are added to the cluster, Pods are added to them. As nodes are removed from the cluster, those Pods are garbage collected. Deleting a DaemonSet will clean up the Pods it created.

Some typical uses of a DaemonSet are:

    running a cluster storage daemon on every node
    running a logs collection daemon on every node
    running a node monitoring daemon on every node

In a simple case, one DaemonSet, covering all nodes, would be used for each type of daemon. A more complex setup might use multiple DaemonSets for a single type of daemon, but with different flags and/or different memory and cpu requests for different hardware types.

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
        system: HeavyMetal
    spec:
      containers:
      - name: www
        image: nginx:alpine
        ports:
        - containerPort: 80
```



```bash
#
kubectl taint nodes --all node-role.kubernetes.io/master-
```

```bash
#
kubectl create -f  ds_01.yaml
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
kubectl get pods -o wide
```

```bash
#
kubectl set image ds ds01 nginx=nginx:latest
```

```bash
#
kubectl describe ds ds01
```

```bash
#
kubectl delete pod ds01-jh2sp
```