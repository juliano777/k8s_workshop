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
  containers:
  - image: nginx
    name: emptydir01
    volumeMounts:
    - mountPath: /foo
      name: foo-volume
  volumes:
  - name: foo-volume
    emptyDir: {}
    
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
emptydir01   1/1     Running   1          18h
</i></pre>




```bash
#
kubectl exec -it emptydir01 -- ls -lhd /foo
```

<pre><i>
drwxrwxrwx 2 root root 6 Jun 27 17:33 /foo
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
apiVersion: v1
kind: Pod
metadata:
  name: emptydir02
  labels:
    app: EMPTYDIR
spec:
  containers:
  - image: nginx
    name: emptydir02
    volumeMounts:
    - mountPath: /foo
      name: foo-volume
  volumes:
  - name: foo-volume
    emptyDir:
      medium: Memory
```



```bash
# 
kubectl apply -f emptydir02.yaml
```



```bash
# 
kubectl get pods -l app=EMPTYDIR
```

<pre><i>
NAME         READY   STATUS    RESTARTS   AGE
emptydir02   1/1     Running   0          15s
</i></pre>