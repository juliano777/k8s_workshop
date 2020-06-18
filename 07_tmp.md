# 


kubectl rollout history ds daemon-set-primeiro

kubectl rollout history ds daemon-set-primeiro --revision=1

kubectl rollout history ds daemon-set-primeiro --revision=2

kubectl rollout undo ds daemon-set-primeiro --to-revision=1

kubectl rollout status ds daemon-set-primeiro 

kubectl describe daemon-set-primeiro-hp4qc | grep -i image:

kubectl delete -f primeiro-daemonset.yaml

vim primeiro-daemonset.yaml

apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: daemon-set-primeiro
spec:
  template:
    metadata:
      labels:
        system: DaemonOne
    spec:
      containers:
      - name: nginx
        image: nginx:1.7.9
        ports:
        - containerPort: 80
  updateStrategy:
    type: RollingUpdate
    
    
kubectl create -f primeiro-daemonset.yaml

kubectl get daemonset

kubectl describe ds daemon-set-primeiro

kubectl get ds daemon-set-primeiro -o yaml | grep -A 2 Strategy

kubectl set image ds daemon-set-primeiro nginx=nginx:1.15.0

kubectl get daemonset

kubectl get pods -o wide

kubectl describe ds daemon-set-primeiro

kubectl rollout history ds daemon-set-primeiro

kubectl rollout history ds daemon-set-primeiro --revision=1

kubectl rollout history ds daemon-set-primeiro --revision=2

kubectl rollout undo ds daemon-set-primeiro --to-revision=1

kubectl rollout status ds daemon-set-primeiro

kubectl delete ds daemon-set-primeiro

