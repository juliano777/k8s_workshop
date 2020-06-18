# 

# vim primeiro-daemonset.yaml
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: daemon-set-primeiro
spec:
  template:
    metadata:
      labels:
        system: Strigus
    spec:
      containers:
      - name: nginx
        image: nginx:1.7.9
        ports:
        - containerPort: 80

# kubectl taint nodes --all node-role.kubernetes.io/master-

# kubectl create -f  primeiro-daemonset.yaml

# kubectl get daemonset

# kubectl describe ds daemon-set-primeiro

# kubectl get pods -o wide

# kubectl set image ds daemon-set-primeiro nginx=nginx:1.15.0

# kubectl describe ds daemon-set-primeiro

# kubectl delete pod daemon-set-primeiro-jh2sp