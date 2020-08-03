# ConfigMap


ConfigMaps allow you to decouple configuration artifacts from image content to keep containerized applications portable. This page provides a series of usage examples demonstrating how to create ConfigMaps and configure Pods using data stored in ConfigMaps.



```bash
# 
echo -n "descomplicando-k8s" > secret.txt
```


```bash
# 
kubectl create secret generic my-secret --from-file=secret.txt
```


```bash
# 
kubectl describe secret my-secret
```

```bash
# 
kubectl get secret
```


```bash
# 
kubectl get secret my-secret -o yaml
```

```bash
# 
echo 'ZGVzY29tcGxpY2FuZG8tazhz' | base64 --decode
```

```bash
# 
vim pod-configmap.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: busybox-configmap
  namespace: default
spec:
  containers:
  - image: busybox
    name: busy-configmap
    command:
      - sleep
      - "3600"
    env:
    - name: frutas
      valueFrom:
        configMapKeyRef:
          name: cores-frutas
          key: predileta
#    envFrom:
#    - configMapRef:
#        name: cores-frutas
```






```bash
# 
kubectl create -f pod-configmap.yaml
```


```bash
# 
cat pod-configmap-file.yaml
```

<pre><i>
apiVersion: v1
kind: Pod
metadata:
  name: busybox-configmap-file
  namespace: default
spec:
  containers:
  - image: busybox
    name: busy-configmap
    command:
      - sleep
      - "3600"
    volumeMounts:
    - name: meu-configmap-vol
      mountPath: /etc/frutas
  volumes:
  - name: meu-configmap-vol
    configMap:
      name: cores-frutas
</i></pre>







```bash
# 
kubectl create -f pod-configmap-file.yaml
```