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

A PersistentVolume (PV) is a piece of storage in the cluster that has been provisioned by an administrator or dynamically provisioned using Storage Classes. It is a resource in the cluster just like a node is a cluster resource. PVs are volume plugins like Volumes, but have a lifecycle independent of any individual Pod that uses the PV. This API object captures the details of the implementation of the storage, be that NFS, iSCSI, or a cloud-provider-specific storage system.

## Política de Reivindicação de Volume Persistente - persistentVolumeReclaimPolicy

Por que mudar uma política de reivindicação de um PersistentVolume?


PersistentVolumes can have various reclaim policies, including "Retain", "Recycle", and "Delete".

This means that a dynamically provisioned volume is automatically deleted when a user deletes the corresponding 



This automatic behavior might be inappropriate if the volume contains precious data.

In that case, it is more appropriate to use the "Retain" policy.

With the "Retain" policy, if a user deletes a PersistentVolumeClaim, the corresponding PersistentVolume is not be deleted.

Instead, it is moved to the Released phase, where all of its data can be manually recovered.

- Retain: 
- Recycle:
- Delete (default): Um volume provisionado é automaticamente removido quando um usuário apaga seu PersistentVolumeClaim.

### PersistentVolumeClaim

A PersistentVolumeClaim (PVC) is a request for storage by a user. It is similar to a Pod. Pods consume node resources and PVCs consume PV resources. Pods can request specific levels of resources (CPU and Memory). Claims can request specific size and access modes (e.g., they can be mounted ReadWriteOnce, ReadOnlyMany or ReadWriteMany, see AccessModes).




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
  capacity:
    storage: 300Mi
  accessModes:
  - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    path: /mnt/pool00
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


<pre><i>

</i></pre>


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



```bash
# 
kubectl get pv
```


<pre><i>
NAME   CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM           STORAGECLASS   REASON   AGE
pv01   300Mi      RWX            Retain           Bound    default/pvc01                           3m27s
</i></pre>



```bash
# 
kubectl get persistentvolumeclaims
```

ou

```bash
# 
kubectl get pvc
```

<pre><i>
NAME    STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc01   Bound    pv01     300Mi      RWX                           98s
</i></pre>

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


```bash
# 
kubectl get pods -l run=www
```





<pre><i>
NAME                        READY   STATUS    RESTARTS   AGE
deploy-pv-6759bfc68-2dpvg   1/1     Running   0          8s
deploy-pv-6759bfc68-glj5n   1/1     Running   0          8s
deploy-pv-6759bfc68-v77lx   1/1     Running   0          8s
</i></pre>



```bash
# 
kubectl exec -it deploy-pv-6759bfc68-2dpvg -- touch /test/blablabla.txt
```





```bash
# 
kubectl exec -it deploy-pv-6759bfc68-v77lx -- ls /test/
```



<pre><i>

</i></pre>

blablabla.txt

```bash
# 
kubectl describe deploy deploy-pv | fgrep -A4 Volumes
```



<pre><i>

</i></pre>

  Volumes:
   test:
    Type:       PersistentVolumeClaim (a reference to a PersistentVolumeClaim in the same namespace)
    ClaimName:  pvc01
    ReadOnly:   false


```bash
# 
kubectl delete -f deploy-pv.yaml
```







<pre><i>

</i></pre>





