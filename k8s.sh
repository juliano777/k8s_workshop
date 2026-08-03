cat << EOF | sudo tee -a /etc/hosts

# Kubertnetes cluster
192.168.56.50   k8s-00.my.domain        k8s-00
192.168.56.51   k8s-01.my.domain        k8s-01
192.168.56.52   k8s-02.my.domain        k8s-02
EOF

sudo swapoff -a
sudo systemctl mask swap.target


# 1. Atualize os pacotes e instale dependências básicas
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl gpg containerd bash-completion

# 2. Baixe a chave pública do repositório do Kubernetes
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# 3. Adicione o repositório do Kubernetes

# allow unprivileged APT programs to read this keyring
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg 


# Adicionar o repositório
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' | \
sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list   # helps tools such as command-not-found to work correctly

sudo apt update
sudo apt install -y kubelet kubeadm kubectl

# Travar a versão para evitar atualizações acidentais
sudo apt-mark hold kubelet kubeadm kubectl


# Carregar os módulos necessários

# 
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'source <(kubeadm completion bash)' >> ~/.bashrc
source ~/.bashrc

cat << EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
# Habilita o roteamento de pacotes (o que causou o erro)
net.ipv4.ip_forward = 1

# Permite que o iptables enxergue o tráfego que passa pela bridge da rede
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Aplica as configurações no kernel imediatamente
sudo sysctl --system


# ============================================================================
# [Master]


# Control Plane
sudo kubeadm init --apiserver-advertise-address=192.168.56.50 --pod-network-cidr=192.168.0.0/16

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config



kubectl get nodes
"
NAME               STATUS     ROLES           AGE     VERSION
k8s-00.my.domain   NotReady   control-plane   3h12m   v1.36.3
"


kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.1/manifests/calico.yaml


kubectl get pods -n kube-system -w

"
NAME                                       READY   STATUS     RESTARTS            AGE
calico-kube-controllers-5cdf4f467d-44l26   0/1     Pending    0                   8s
calico-node-r24wt                          0/1     Init:0/3   0                   8s
coredns-589f44dc88-kjvcb                   0/1     Pending    0                   13m
coredns-589f44dc88-knv82                   0/1     Pending    0                   13m
etcd-k8s-00.my.domain                      1/1     Running    2 (<invalid> ago)   13m
kube-apiserver-k8s-00.my.domain            1/1     Running    2 (<invalid> ago)   13m
kube-controller-manager-k8s-00.my.domain   1/1     Running    2 (<invalid> ago)   13m
kube-proxy-86qsc                           1/1     Running    2 (<invalid> ago)   13m
kube-scheduler-k8s-00.my.domain            0/1     Running    2 (<invalid> ago)   13m
calico-node-r24wt                          0/1     Init:0/3   0                   8s
calico-node-r24wt                          0/1     Init:1/3   0                   10s
calico-node-r24wt                          0/1     Init:1/3   0                   10s
coredns-589f44dc88-knv82                   0/1     Pending    0                   13m
coredns-589f44dc88-kjvcb                   0/1     Pending    0                   13m
calico-kube-controllers-5cdf4f467d-44l26   0/1     Pending    0                   11s
coredns-589f44dc88-knv82                   0/1     ContainerCreating   0                   13m
coredns-589f44dc88-kjvcb                   0/1     ContainerCreating   0                   13m
calico-kube-controllers-5cdf4f467d-44l26   0/1     ContainerCreating   0                   11s
calico-node-r24wt                          0/1     Init:2/3            0                   12s
calico-node-r24wt                          0/1     Init:2/3            0                   22s
calico-node-r24wt                          0/1     PodInitializing     0                   24s
calico-node-r24wt                          0/1     Running             0                   24s
calico-node-r24wt                          0/1     Running             0                   44s
"

kubectl get nodes
NAME               STATUS   ROLES           AGE   VERSION
k8s-00.my.domain   Ready    control-plane   15m   v1.36.3



kubeadm token create --print-join-command
"kubeadm join 10.0.2.15:6443 --token p7f3tn.tzz1ym41i8rh0vo3 --discovery-token-ca-cert-hash sha256:ea289e2910b24abc19c17beb40f9ea461e922f13b995b79df96e1613d42f86d0"


sudo kubeadm join 192.168.56.50:6443 --token 2rg77o.p5a0ldg2jkce2i0y \
	--discovery-token-ca-cert-hash sha256:4c9fb502d497f9b41885113482134ef7ee0c59b2d8c0548fee6f3b0d6c85b849 


kubectl get nodes
"
NAME               STATUS     ROLES           AGE   VERSION
k8s-00.my.domain   Ready      control-plane   36m   v1.36.3
k8s-01.my.domain   Ready      <none>          54s   v1.36.3
k8s-02.my.domain   NotReady   <none>          6s    v1.36.3
"


kubectl get nodes -o wide
NAME               STATUS   ROLES           AGE     VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE                       KERNEL-VERSION                 CONTAINER-RUNTIME
k8s-00.my.domain   Ready    control-plane   3h33m   v1.36.3   192.168.56.50   <none>        Debian GNU/Linux 13 (trixie)   6.12.100+deb13-arm64 (arm64)   containerd://1.7.24
k8s-01.my.domain   Ready    <none>          177m    v1.36.3   192.168.56.51   <none>        Debian GNU/Linux 13 (trixie)   6.12.100+deb13-arm64 (arm64)   containerd://1.7.24
k8s-02.my.domain   Ready    <none>          176m    v1.36.3   192.168.56.52   <none>        Debian GNU/Linux 13 (trixie)   6.12.100+deb13-arm64 (arm64)   containerd://1.7.24


kubectl get nodes --show-labels
NAME               STATUS   ROLES           AGE     VERSION   LABELS
k8s-00.my.domain   Ready    control-plane   3h33m   v1.36.3   beta.kubernetes.io/arch=arm64,beta.kubernetes.io/os=linux,kubernetes.io/arch=arm64,kubernetes.io/hostname=k8s-00.my.domain,kubernetes.io/os=linux,node-role.kubernetes.io/control-plane=,node.kubernetes.io/exclude-from-external-load-balancers=
k8s-01.my.domain   Ready    <none>          178m    v1.36.3   beta.kubernetes.io/arch=arm64,beta.kubernetes.io/os=linux,kubernetes.io/arch=arm64,kubernetes.io/hostname=k8s-01.my.domain,kubernetes.io/os=linux
k8s-02.my.domain   Ready    <none>          177m    v1.36.3   beta.kubernetes.io/arch=arm64,beta.kubernetes.io/os=linux,kubernetes.io/arch=arm64,kubernetes.io/hostname=k8s-02.my.domain,kubernetes.io/os=linux

kubectl run my-first-pod --image=nginx

kubectl get pods
NAME           READY   STATUS              RESTARTS   AGE
my-first-pod   0/1     ContainerCreating   0          18s


kubectl run my-site --image=nginx

kubectl get pods.
NAME           READY   STATUS              RESTARTS   AGE
my-first-pod   0/1     ContainerCreating   0          4m36s
my-site        0/1     ContainerCreating   0          24s


kubectl get pods -o wide
NAME           READY   STATUS              RESTARTS   AGE    IP       NODE               NOMINATED NODE   READINESS GATES
my-first-pod   0/1     ContainerCreating   0          5m5s   <none>   k8s-02.my.domain   <none>           <none>
my-site        0/1     ContainerCreating   0          53s    <none>   k8s-01.my.domain   <none>           <none>


# Nós workers: ============================================================================

sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo mkdir -p /opt/cni
sudo ln -s /usr/lib/cni /opt/cni/bin
sudo mkdir -p /usr/lib/cni
sudo cp -r /opt/cni/bin/* /usr/lib/cni/


sudo ctr -n k8s.io images pull docker.io/library/nginx:latest

  sudo reboot

# =========================================================================================


kubectl delete pod my-first-pod my-site 
pod "my-first-pod" deleted from default namespace
pod "my-site" deleted from default namespace


kubectl run my-first-pod --image=nginx
kubectl run my-site --image=nginx


kubectl get pods -o wide
NAME           READY   STATUS    RESTARTS   AGE   IP                NODE               NOMINATED NODE   READINESS GATES
my-first-pod   1/1     Running   0          42s   192.168.15.130    k8s-02.my.domain   <none>           <none>
my-site        1/1     Running   0          25s   192.168.149.194   k8s-01.my.domain   <none>           <none>



curl 192.168.149.194
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, nginx is successfully installed and working.
Further configuration is required for the web server, reverse proxy, 
API gateway, load balancer, content cache, or other features.</p>

<p>For online documentation and support please refer to
<a href="https://nginx.org/">nginx.org</a>.<br/>
To engage with the community please visit
<a href="https://community.nginx.org/">community.nginx.org</a>.<br/>
For enterprise grade support, professional services, additional 
security features and capabilities please refer to
<a href="https://f5.com/nginx">f5.com/nginx</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>


kubectl run testyaml --image=alpine --dry-run=client -o yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: testyaml
  name: testyaml
spec:
  containers:
  - image: alpine
    name: testyaml
    resources: {}
  dnsPolicy: ClusterFirst
  restartPolicy: Always
status: {}


kubectl run testyaml --image=alpine --dry-run=client -o yaml > testyaml.yaml

kubectl create deployment web-server --image=nginx --dry-run=client -o yaml > deployment.yaml

cat deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: web-server
  name: web-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web-server
  strategy: {}
  template:
    metadata:
      labels:
        app: web-server
    spec:
      containers:
      - image: nginx
        name: nginx
        resources: {}
status: {}


Dissecando o Capataz (Deployment)
Repare que o YAML de um Deployment é basicamente um Pod dentro de um envelope.

replicas: 1: É aqui que dizemos ao capataz quantos clones nós queremos rodando ao mesmo tempo.

template:: Tudo que está daqui para baixo é exatamente o molde do Pod! É a receita de bolo que o capataz vai usar toda vez que precisar criar um pod novo.

selector: e labels:: É como o capataz rastreia os "funcionários" dele. Ele vai olhar para o cluster e dizer: "Todos os pods que tiverem a etiqueta app: web-server são meus. Se algum morrer, eu crio outro igual".

Colocando a mágica para funcionar
Agora vamos aplicar esse documento de forma definitiva (Abordagem Declarativa). Rode o comando:


kubectl apply -f deployment.yaml

kubectl get deployments
NAME         READY   UP-TO-DATE   AVAILABLE   AGE
web-server   1/1     1            1           6s

kubectl get pods -o wide
NAME                          READY   STATUS             RESTARTS       AGE     IP                NODE               NOMINATED NODE   READINESS GATES
my-first-pod                  1/1     Running            0              18m     192.168.15.130    k8s-02.my.domain   <none>           <none>
my-site                       1/1     Running            0              17m     192.168.149.194   k8s-01.my.domain   <none>           <none>
testyaml                      0/1     CrashLoopBackOff   6 (3m4s ago)   8m51s   192.168.15.131    k8s-02.my.domain   <none>           <none>
web-server-6589dbb6cd-c8vww   1/1     Running            0              26s     192.168.149.195   k8s-01.my.domain   <none>           <none>


kubectl get pods -o wide
NAME                          READY   STATUS      RESTARTS       AGE   IP                NODE               NOMINATED NODE   READINESS GATES
my-first-pod                  1/1     Running     0              21m   192.168.15.130    k8s-02.my.domain   <none>           <none>
my-site                       1/1     Running     0              20m   192.168.149.194   k8s-01.my.domain   <none>           <none>
testyaml                      0/1     Completed   7 (6m4s ago)   11m   192.168.15.131    k8s-02.my.domain   <none>           <none>
web-server-6589dbb6cd-xclvk   1/1     Running     0              49s   192.168.15.132    k8s-02.my.domain   <none>           <none>
tux@k8s-00:~$ kubectl delete pod web-server-6589dbb6cd-xclvk
pod "web-server-6589dbb6cd-xclvk" deleted from default namespace
tux@k8s-00:~$ kubectl get pods -o wide
NAME                          READY   STATUS      RESTARTS        AGE   IP                NODE               NOMINATED NODE   READINESS GATES
my-first-pod                  1/1     Running     0               21m   192.168.15.130    k8s-02.my.domain   <none>           <none>
my-site                       1/1     Running     0               21m   192.168.149.194   k8s-01.my.domain   <none>           <none>
testyaml                      0/1     Completed   7 (6m27s ago)   12m   192.168.15.131    k8s-02.my.domain   <none>           <none>
web-server-6589dbb6cd-rmmv2   1/1     Running     0               10s   192.168.149.196   k8s-01.my.domain   <none>           <none>

kubectl scale deployment web-server --replicas=5
deployment.apps/web-server scaled
tux@k8s-00:~$ kubectl get pods -o wide
NAME                          READY   STATUS             RESTARTS        AGE   IP                NODE               NOMINATED NODE   READINESS GATES
my-first-pod                  1/1     Running            0               22m   192.168.15.130    k8s-02.my.domain   <none>           <none>
my-site                       1/1     Running            0               22m   192.168.149.194   k8s-01.my.domain   <none>           <none>
testyaml                      0/1     CrashLoopBackOff   7 (2m31s ago)   13m   192.168.15.131    k8s-02.my.domain   <none>           <none>
web-server-6589dbb6cd-4fqt9   1/1     Running            0               19s   192.168.15.133    k8s-02.my.domain   <none>           <none>
web-server-6589dbb6cd-7q968   1/1     Running            0               19s   192.168.15.134    k8s-02.my.domain   <none>           <none>
web-server-6589dbb6cd-bvjzc   1/1     Running            0               19s   192.168.149.198   k8s-01.my.domain   <none>           <none>
web-server-6589dbb6cd-cc9f4   1/1     Running            0               19s   192.168.149.197   k8s-01.my.domain   <none>           <none>
web-server-6589dbb6cd-rmmv2   1/1     Running            0               93s   192.168.149.196   k8s-01.my.domain   <none>           <none>

kubectl expose deployment web-server --port=80 --type=NodePort
service/web-server exposed
tux@k8s-00:~$ kubectl get svc
NAME         TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
kubernetes   ClusterIP   10.96.0.1      <none>        443/TCP        4h30m
web-server   NodePort    10.111.186.0   <none>        80:30607/TCP   7s
tux@k8s-00:~$ kubectl get svc web-server
NAME         TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
web-server   NodePort   10.111.186.0   <none>        80:30607/TCP   78s
tux@k8s-00:~$ kubectl get nodes -o wide
NAME               STATUS   ROLES           AGE     VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE                       KERNEL-VERSION                 CONTAINER-RUNTIME
k8s-00.my.domain   Ready    control-plane   4h31m   v1.36.3   192.168.56.50   <none>        Debian GNU/Linux 13 (trixie)   6.12.100+deb13-arm64 (arm64)   containerd://1.7.24
k8s-01.my.domain   Ready    <none>          3h56m   v1.36.3   192.168.56.51   <none>        Debian GNU/Linux 13 (trixie)   6.12.100+deb13-arm64 (arm64)   containerd://1.7.24
k8s-02.my.domain   Ready    <none>          3h55m   v1.36.3   192.168.56.52   <none>        Debian GNU/Linux 13 (trixie)   6.12.100+deb13-arm64 (arm64)   containerd://1.7.24


curl http://192.168.56.50:30607
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, nginx is successfully installed and working.
Further configuration is required for the web server, reverse proxy, 
API gateway, load balancer, content cache, or other features.</p>

<p>For online documentation and support please refer to
<a href="https://nginx.org/">nginx.org</a>.<br/>
To engage with the community please visit
<a href="https://community.nginx.org/">community.nginx.org</a>.<br/>
For enterprise grade support, professional services, additional 
security features and capabilities please refer to
<a href="https://f5.com/nginx">f5.com/nginx</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>



