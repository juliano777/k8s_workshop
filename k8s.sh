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

# Baixar a chave pública
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | \
sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

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



