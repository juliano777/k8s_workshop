# Taints

kubectl describe nodes k8s-02 | fgrep Taints

Taints:             <none>



kubectl describe nodes k8s-01 | fgrep Taints

Taints:             node-role.kubernetes.io/master:NoSchedule



kubectl get pods -o wide



kubectl get nodes | awk '{print $1}'
NAME
k8s-01
k8s-02.local
k8s-03.local



kubectl taint node k8s-03.local key1=value1:NoSchedule



kubectl scale --replicas=10 deployment deploy-wwww



kubectl get pods -o wide | fgrep k8s-03 | wc -l

3



kubectl get pods -o wide | fgrep k8s-02 | wc -l

7



# Remove o taint
kubectl taint node k8s-03.local key1:NoSchedule-



kubectl scale --replicas=1 deployment deploy-wwww



kubectl scale --replicas=8 deployment deploy-wwww



kubectl get pods -o wide | fgrep k8s-02 | wc -l

4



kubectl get pods -o wide | fgrep k8s-03 | wc -l

4



kubectl taint node k8s-02.local key1=valu1:NoExecute



kubectl get pods -o wide | fgrep k8s-02 | wc -l

0



kubectl get pods -o wide | fgrep k8s-03 | wc -l

8



kubectl taint node k8s-02.local key1:NoExecute-



kubectl scale deployment --replicas=1 deploy-wwww 



kubectl scale deployment --replicas=10 deploy-wwww 



kubectl get pods -o wide | fgrep k8s-02 | wc -l

6



kubectl get pods -o wide | fgrep k8s-02 | wc -l

6


kubectl get pods -o wide | fgrep k8s-02 | wc -l

6


kubectl get pods -o wide | fgrep k8s-03 | wc -l

4
