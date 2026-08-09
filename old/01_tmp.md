# Limitando Recursos

kubectl edit deployments deploy-wwww

kubectl exec -it <container> -- bash

apt update && apt install -y stress

stress --vm 1 --vm-bytes 128M --cpu 1  # E vai aumentando os números conforme os limites

kubectl get <tipo_objeto> <nome_objeto> -o yaml  # Printa na tela o YAML para construção do objeto.


kubectk get limitranges -n <namespace>



vim limitando-recursos.yaml

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: limitando-recursos
spec:
  limits:
  - default:
      cpu: 1
      memory: 100Mi
    defaultRequest:
      cpu: 0.5
      memory: 80Mi
    type: Container
```



kubectl apply -f limitando-recursos.yaml



vim pod-limitrange.yml



```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-limitrange
spec:
  containers:
    - name: limitado-pod
      image: nginx
```



kubectl create namespace primeiro-namespace



kubectl get ns

NAME                 STATUS   AGE
default              Active   21d
kube-node-lease      Active   21d
kube-public          Active   21d
kube-system          Active   21d
nsfoo                Active   21d
primeiro-namespace   Active   7s



kubectl describe namespace primeiro-namespace

Name:         primeiro-namespace
Labels:       <none>
Annotations:  <none>
Status:       Active

No resource quota.

No LimitRange resource.



kubectl apply -f limitando-recursos.yaml -n primeiro-namespace



kubectl apply -f limitando-recursos.yaml -n primeiro-namespace



kubectl describe namespace primeiro-namespace

Name:         primeiro-namespace
Labels:       <none>
Annotations:  <none>
Status:       Active

No resource quota.

Resource Limits
 Type       Resource  Min  Max  Default Request  Default Limit  Max Limit/Request Ratio
 ----       --------  ---  ---  ---------------  -------------  -----------------------
 Container  cpu       -    -    500m             1              -
 Container  memory    -    -    80Mi             100Mi          -



kubectl get limitranges



kubectl get limitranges -n primeiro-namespace

NAME                 CREATED AT
limitando-recursos   2020-06-03T18:21:25Z



kubectl describe limitranges -n primeiro-namespace

Name:       limitando-recursos
Namespace:  primeiro-namespace
Type        Resource  Min  Max  Default Request  Default Limit  Max Limit/Request Ratio
----        --------  ---  ---  ---------------  -------------  -----------------------
Container   cpu       -    -    500m             1              -
Container   memory    -    -    80Mi             100Mi          -



kubectl apply -f pod-limitrange.yml -n primeiro-namespace



kubectl -n primeiro-namespace get pods

NAME             READY   STATUS    RESTARTS   AGE
pod-limitrange   1/1     Running   0          31s



kubectl -n primeiro-namespace describe pod pod-limitrange

Name:         pod-limitrange
Namespace:    primeiro-namespace
Priority:     0
Node:         k8s-03.local/192.168.56.30
Start Time:   Wed, 03 Jun 2020 15:29:19 -0300
Labels:       <none>
Annotations:  cni.projectcalico.org/podIP: 192.168.86.132/32
              cni.projectcalico.org/podIPs: 192.168.86.132/32
              kubernetes.io/limit-ranger:
                LimitRanger plugin set: cpu, memory request for container limitado-pod; cpu, memory limit for container limitado-pod
Status:       Running
IP:           192.168.86.132
IPs:
  IP:  192.168.86.132
Containers:
  limitado-pod:
    Container ID:   docker://a7c0cd0644f929abb74653012b235c5cc465718766555bbc78efc5905016d1d2
    Image:          nginx
    Image ID:       docker-pullable://nginx@sha256:883874c218a6c71640579ae54e6952398757ec65702f4c8ba7675655156fcca6
    Port:           <none>
    Host Port:      <none>
    State:          Running
      Started:      Wed, 03 Jun 2020 15:29:23 -0300
    Ready:          True
    Restart Count:  0
    Limits:
      cpu:     1
      memory:  100Mi
    Requests:
      cpu:        500m
      memory:     80Mi
    Environment:  <none>
    Mounts:
      /var/run/secrets/kubernetes.io/serviceaccount from default-token-snjpf (ro)
Conditions:
  Type              Status
  Initialized       True 
  Ready             True 
  ContainersReady   True 
  PodScheduled      True 
Volumes:
  default-token-snjpf:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  default-token-snjpf
    Optional:    false
QoS Class:       Burstable
Node-Selectors:  <none>
Tolerations:     node.kubernetes.io/not-ready:NoExecute for 300s
                 node.kubernetes.io/unreachable:NoExecute for 300s
Events:
  Type    Reason     Age   From                   Message
  ----    ------     ----  ----                   -------
  Normal  Scheduled  82s   default-scheduler      Successfully assigned primeiro-namespace/pod-limitrange to k8s-03.local
  Normal  Pulling    81s   kubelet, k8s-03.local  Pulling image "nginx"
  Normal  Pulled     79s   kubelet, k8s-03.local  Successfully pulled image "nginx"
  Normal  Created    79s   kubelet, k8s-03.local  Created container limitado-pod
  Normal  Started    78s   kubelet, k8s-03.local  Started container limitado-pod