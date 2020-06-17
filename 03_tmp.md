# Deployments

Um deployment fornece atualizações declarativas para Pods e ReplicaSets.

Descreve-se um estado desejado em um Deployment e o Controller do Deployment muda o atual estado para o estado desejado a uma taxa controlada.

Um Deployment pode ser definido para criar novos ReplicaSets ou remover Deployments existentes e adotar todos seus recursos com novos Deployments.



```bash
# Criação do YAML do deployment:
vim deploy_01.yaml
```


```yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  labels:
    run: nginx
    app: heavymetal
  name: deploy01
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      run: nginx
  template:
    metadata:
      labels:
        run: nginx
        color: Green
    spec:
      containers:
      - image: nginx
        imagePullPolicy: Always
        name: nginx2
        ports:
        - containerPort: 80
          protocol: TCP
        resources: {}
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      schedulerName: default-scheduler
      securityContext: {}
      terminationGracePeriodSeconds: 30
```



```bash
# Aplicando o YAML:
kubectl apply -f deploy_01.yaml
```





