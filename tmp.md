```bash
# 
vim job-mixed.yaml
```

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: sleep-mixed
  labels:
    myJob: SleeperMixed
spec:
  completions: 10
  parallelism: 5
  template:
    metadata:
      labels:
        myJob: SleeperMixed
    spec:
      containers:
      - name: sleeper
        image: alpine
        command:
        - "sh"
        - "-c"
        - "for i in `seq 0 9`; do echo $i; sleep 1; done"
      restartPolicy: Never
```



```bash
# 
kubectl apply -f job-mixed.yaml
```



```bash
# Verificar os pods desse job:
kubectl get pods -l myJob=SleeperMixed
```

<pre><i>
NAME                READY   STATUS              RESTARTS   AGE
sleep-mixed-5rtk7   1/1     Running             0          6s
sleep-mixed-ccf79   0/1     ContainerCreating   0          6s
sleep-mixed-cv8fr   0/1     ContainerCreating   0          6s
sleep-mixed-f68v5   1/1     Running             0          6s
sleep-mixed-vvh96   0/1     ContainerCreating   0          6s
</i></pre>

Ao definir o paralelismo para 5, nota-se que isso é mantido ao constar-se que
foram lançados 5 (cinco) pods iniciais.



```bash
# 
kubectl get jobs -l myJob=SleeperMixed
```

<pre><i>
NAME          COMPLETIONS   DURATION   AGE
sleep-mixed   10/10         37s        60s
</i></pre>



```bash
# 
kubectl delete -f job-mixed.yaml
```