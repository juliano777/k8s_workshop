# Secret

Kubernetes Secrets let you store and manage sensitive information, such as passwords, OAuth tokens, and ssh keys. Storing confidential information in a Secret is safer and more flexible than putting it verbatim in a Pod definition or in a container image . See Secrets design document for more information.
Overview of Secrets

A Secret is an object that contains a small amount of sensitive data such as a password, a token, or a key. Such information might otherwise be put in a Pod specification or in an image. Users can create secrets and the system also creates some secrets.

To use a secret, a Pod needs to reference the secret. A secret can be used with a Pod in three ways:

    As files in a volume mounted on one or more of its containers.
    As container environment variable.
    By the kubelet when pulling images for the Pod.



## Secret a Partir de um Arquivo



```bash
# 
echo -n 'Veni vidi vici!' > secret-01.txt
```



```bash
# 
kubectl create secret generic secret-01 --from-file=secret-01.txt
```



```bash
# 
kubectl describe secret secret-01
```

<pre><i>
Name:         secret-01
Namespace:    default
Labels:       <none>
Annotations:  <none>

Type:  Opaque

Data
====
secret-01.txt:  15 bytes
</i></pre>



```bash
# 
kubectl get secrets secret-01 -o yaml
```

<pre><i>
apiVersion: v1
data:
  secret-01.txt: VmVuaSB2aWRpIHZpY2kh
kind: Secret
metadata:
  creationTimestamp: "2020-08-02T14:46:39Z"
  managedFields:
  - apiVersion: v1
    fieldsType: FieldsV1
    fieldsV1:
      f:data:
        .: {}
        f:secret-01.txt: {}
      f:type: {}
    manager: kubectl
    operation: Update
    time: "2020-08-02T14:46:39Z"
  name: secret-01
  namespace: default
  resourceVersion: "304270"
  selfLink: /api/v1/namespaces/default/secrets/secret-01
  uid: 8828887a-0a1b-4be3-9438-bbba323e2529
type: Opaque
</i></pre>



```bash
# 
echo 'VmVuaSB2aWRpIHZpY2kh' | base64 --decode
```

<pre><i>
Veni vidi vici!
</i></pre>

## Secret em um Volume

```bash
# 
vim pod-vol-secret.yaml
```



```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-secret-volume
spec:
  containers:
  - image: alpine
    name: psv
    command:
      - sleep
      - '3600'
    volumeMounts:
    - mountPath: /tmp/secret
      name: vol-secret
  volumes:
  - name: vol-secret
    secret:
      secretName: secret-01
```



```bash
# 
kubectl apply -f pod-vol-secret.yaml
```



```bash
# 
kubectl get pods
```

<pre><i>
NAME                READY   STATUS              RESTARTS   AGE
pod-secret-volume   0/1     ContainerCreating   0          2m3s
</i></pre>



```bash
# 
kubectl exec -it pod-secret-volume -- cat /tmp/secret/secret-01.txt
```

<pre><i>
Veni vidi vici!
</i></pre>



```bash
# 
kubectl delete -f pod-vol-secret.yaml
```



## Secret Literal


```bash
# 
kubectl create secret generic secret-02 \
    --from-literal user=foo --from-literal password=bar
```



```bash
# 
kubectl get secrets secret-02
```

<pre><i>
NAME        TYPE     DATA   AGE
secret-02   Opaque   2      72s
</i></pre>



```bash
# 
kubectl get secrets secret-02 -o yaml
```





<pre><i>
apiVersion: v1
data:
  password: YmFy
  user: Zm9v
kind: Secret
metadata:
  creationTimestamp: "2020-08-02T15:21:02Z"
  managedFields:
  - apiVersion: v1
    fieldsType: FieldsV1
    fieldsV1:
      f:data:
        .: {}
        f:password: {}
        f:user: {}
      f:type: {}
    manager: kubectl
    operation: Update
    time: "2020-08-02T15:21:02Z"
  name: secret-02
  namespace: default
  resourceVersion: "309261"
  selfLink: /api/v1/namespaces/default/secrets/secret-02
  uid: d6373e10-2d7c-45e3-96cf-bade04b21b62
type: Opaque
</i></pre>





## Secret para uma Variável de Ambiente




```bash
# 
vim pod-env-secret.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-secret-env
spec:
  containers:
  - image: alpine
    name: secret-env
    command:
      - sleep
      - '3600'
    env:
    - name: USUARIO
      valueFrom:
        secretKeyRef:
          name: secret-02
          key: user
    - name: SENHA
      valueFrom:
        secretKeyRef:
          name: secret-02
          key: password
```



```bash
# 
kubectl apply -f pod-env-secret.yaml
```



```bash
# 
kubectl get pods
```

<pre><i>
NAME             READY   STATUS      RESTARTS   AGE
pod-secret-env   1/1     Running     0          15s
</i></pre>



```bash
# 
kubectl exec -it pod-secret-env -- env | egrep 'USUARIO|SENHA'
```

<pre><i>
USUARIO=foo
SENHA=bar
</i></pre>