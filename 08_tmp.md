# Volumes

On-disk files in a Container are ephemeral, which presents some problems for non-trivial applications when running in Containers.
First, when a Container crashes, kubelet will restart it, but the files will be lost - the Container starts with a clean state. Second, when running Containers together in a Pod it is often necessary to share files between those Containers. The Kubernetes Volume abstraction solves both of these problems.

## emptyDir

 When a Pod is removed from a node for any reason, the data in the emptyDir is deleted forever.

Um volume emptyDir é primeiro criado quando um Pod é assimilado a um nó e existe enquanto o Pod estiver rodando nesse nó. Como o nome diz, é inicialmente vazio.
Contêineres no pod podem todos ler e escrever os mesmos arquivos, embora esse volume possa ser montado com os mesmos paths ou diferentes em cada contêiner.

Alguns exemplos de uso:

* Espaço de trabalho, como para classificação de mesclagem baseada em disco;
* Verificação de um cálculo longo para recuperação de falhas;
* Mantendo arquivos que um contêiner gerenciador de conteúdo busca enquanto um contêiner de servidor web serve os dados.

Por padrão, volumes emptyDir são armazenados em qualquer tipo de mídia no nó, que pode ser disco, SSD ou network storage, dependendo do ambiente.
Porém, pode-se configurar o campo `emptyDir.medium` como "`Memory`" para fazer o Kubernetes montar um _tmpfs_ (sistema de arquivos baseado em RAM).
Vale lembrar que tmpfs é muito rápido, mas ao contrário de discos, os dados em RAM vão embora ao desligar a máquina ou num reboot e também o que for nele gravado contará contra o limite de memória.


```bash
# 
vim emptydir01.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: emptydir01
  labels:
    app: EMPTYDIR  
spec:
  volumes:
  - name: html
    emptyDir: {}
  - name: tmp
    emptyDir:
      medium: Memory
      sizeLimit: 256M 
  containers:
  - name: www
    image: nginx
    volumeMounts:
    - name: html
      mountPath: /usr/share/nginx/html
    - name: tmp
      mountPath: /tmp
  - name: test
    image: alpine
    volumeMounts:
    - name: tmp
      mountPath: /tmp    
    command: ["/bin/sh", "-c"]
    args:
      - while true; do
          sleep 1;
        done
```



```bash
# 
kubectl apply -f emptydir01.yaml
```



```bash
#
kubectl get pods -l app=EMPTYDIR
```

<pre><i>
NAME         READY   STATUS    RESTARTS   AGE
emptydir01   2/2     Running   0          5m56s
</i></pre>




```bash
#
kubectl exec -it emptydir01 -c www -- cat /etc/os-release | egrep '^NAME='
```

<pre><i>
NAME="Debian GNU/Linux"
</i></pre>



```bash
#
kubectl exec -it emptydir01 -c test -- cat /etc/os-release | egrep '^NAME='
```

<pre><i>
NAME="Alpine Linux"
</i></pre>



```bash
#
kubectl describe pod emptydir01 | fgrep -A2 Volume
```

<pre><i>
Volumes:
  foo-volume:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
</i></pre>



```bash
#
kubectl delete -f emptydir01.yaml
```



```bash
# 
vim emptydir02.yaml
```

```yaml
 
```



```bash
# 
kubectl apply -f emptydir02.yaml
```



```bash
# Descubra em qual node está rodando o pod:
kubectl get pods -l app=EMPTYDIR -o wide
```

<pre><i>
NAME         READY   STATUS    RESTARTS   AGE   IP              NODE           NOMINATED NODE   READINESS GATES
emptydir02   1/1     Running   0          10m   11.36.224.204   k8s-03.local   <none>           <none>
</i></pre>



```bash
# No node onde está rodando o pod veja o volume montado:
df -h | fgrep 'foo-volume'
```

<pre><i>
tmpfs           984M     0  984M   0% /var/lib/kubelet/pods/3d0d39e0-ca77-4149-bb23-6e8617e5f9b2/volumes/kubernetes.io~empty-dir/foo-volume
</i></pre>



## PersistentVolume


# Servidor NFS

mkdir /opt/test

echo '/opt/test *(rw,sync,no_root_squash,subtree_check)' > /etc/exports

exportfs -ra


# k8s


```bash
# 
vim pv01.yaml
```


```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv01
spec:
  accessModes:
  - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    path: /opt/test
    server: 192.168.56.80
    readOnly: false
```



```bash
# 
kubectl apply -f pv01.yaml
```



kubectl get persistentvolume

ou

kubectl get pv

NAME   CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   REASON   AGE
pv01   300Mi      RWX            Retain           Available                                   2m5s



```bash
# 
vim pvc01.yaml
```


```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc01
spec:
  volumeName: pv01
  accessModes:
  - ReadWriteMany
```



```bash
# 
kubectl apply -f pvc01.yaml
```


kubectl get pv

NAME   CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM           STORAGECLASS   REASON   AGE
pv01   300Mi      RWX            Retain           Bound    default/pvc01                           3m27s



kubectl get persistentvolumeclaims

ou

kubectl get pvc

NAME    STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc01   Bound    pv01     300Mi      RWX                           98s



```bash
# 
vim deploy-pv.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    run: www
  name: deploy-pv
spec:
  replicas: 3
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      run: www
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      labels:
        run: www
    spec:
      containers:
      - image: nginx
        name: web
        volumeMounts:
        - name: test
          mountPath: /test
      volumes:
      - name: test
        persistentVolumeClaim:
          claimName: pvc01
```



```bash
# 
kubectl apply -f deploy-pv.yaml
```



kubectl get pods -l run=www

NAME                        READY   STATUS    RESTARTS   AGE
deploy-pv-6759bfc68-2dpvg   1/1     Running   0          8s
deploy-pv-6759bfc68-glj5n   1/1     Running   0          8s
deploy-pv-6759bfc68-v77lx   1/1     Running   0          8s





kubectl exec -it deploy-pv-6759bfc68-2dpvg -- touch /test/blablabla.txt



kubectl exec -it deploy-pv-6759bfc68-v77lx -- ls /test/

blablabla.txt



kubectl describe deploy deploy-pv | fgrep -A4 Volumes

  Volumes:
   test:
    Type:       PersistentVolumeClaim (a reference to a PersistentVolumeClaim in the same namespace)
    ClaimName:  pvc01
    ReadOnly:   false


kubectl delete -f deploy-pv.yaml    











## PersistentVolumeClaim