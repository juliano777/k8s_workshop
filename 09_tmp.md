# Job

A Job creates one or more Pods and ensures that a specified number of them successfully terminate. As pods successfully complete, the Job tracks the successful completions. When a specified number of successful completions is reached, the task (ie, Job) is complete. Deleting a Job will clean up the Pods it created.

A simple case is to create one Job object in order to reliably run one Pod to completion. The Job object will start a new Pod if the first Pod fails or is deleted (for example due to a node hardware failure or a node reboot).

You can also use a Job to run multiple Pods in parallel.
Running an example Job
Here is an example Job config. It computes π to 2000 places and prints it out. It takes around 10s to complete.

<!-- https://kubernetes.io/docs/concepts/workloads/controllers/job/ -->



## Single Job

Um único job é adequado para fazer testes unitários, testar contêineres ou para aplicações batch.
Normalmente, apenas um pod é iniciado, a não ser que o pod falhe.
O job é finalizado assim que seu pod termina de forma bem sucedida.


```bash
# 
vim job-single.yaml
```



```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: sleep
  labels:
    myJob: Sleeper
spec:
  template:
    metadata:
      labels:
        myJob: Sleeper
    spec:
      containers:
      - name: sleeper
        image: alpine
        command:
        - "sh"
        - "-c"
        - "for i in `seq 0 4`; do echo $i; sleep 1; done"
      restartPolicy: Never
```



```bash
# 
kubectl apply -f job-single.yaml
```



```bash
# 
kubectl get jobs -l myJob=Sleeper
```

<pre><i>
NAME    COMPLETIONS   DURATION   AGE
sleep   0/1           10s        10s
</i></pre>



```bash
# 
kubectl get pods -l myJob=Sleeper
```

<pre><i>
NAME          READY   STATUS    RESTARTS   AGE
sleep-nhssr   1/1     Running   0          6s
</i></pre>



```bash
# 
kubectl logs sleep-nhssr
```


<pre><i>
0
1
2
3
4
</i></pre>



```bash
# 
kubectl get pods -l myJob=Sleeper
```

<pre><i>
NAME          READY   STATUS      RESTARTS   AGE
sleep-nhssr   0/1     Completed   0          58s
</i></pre>



```bash
# 
kubectl get jobs -l myJob=Sleeper
```

<pre><i>
NAME    COMPLETIONS   DURATION   AGE
sleep   1/1           22s        92s
</i></pre>



```bash
# 
kubectl describe jobs sleep
```

<pre><i>
Name:           sleep
Namespace:      default
Selector:       controller-uid=003497cd-7a7b-4286-ab39-9bcc8115703d
Labels:         myJob=Sleeper
Annotations:    Parallelism:  1
Completions:    1
Start Time:     Fri, 10 Jul 2020 08:25:47 -0300
Completed At:   Fri, 10 Jul 2020 08:26:09 -0300
Duration:       22s
Pods Statuses:  0 Running / 1 Succeeded / 0 Failed
Pod Template:
  Labels:  controller-uid=003497cd-7a7b-4286-ab39-9bcc8115703d
           job-name=sleep
           myJob=Sleeper
  Containers:
   sleeper:
    Image:      alpine
    Port:       <none>
    Host Port:  <none>
    Command:
      sh
      -c
      for i in `seq 0 15`; do echo $i; sleep 1; done
    Environment:  <none>
    Mounts:       <none>
  Volumes:        <none>
Events:
  Type    Reason            Age   From            Message
  ----    ------            ----  ----            -------
  Normal  SuccessfulCreate  2m2s  job-controller  Created pod: sleep-nhssr
  Normal  Completed         100s  job-controller  Job completed
</i></pre>



```bash
# 
kubectl delete -f job-single.yaml
```



## Múltiplos Jobs



### Completions


```bash
# 
vim job-completion.yaml
```

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: sleep-completion
  labels:
    myJob: SleeperCompletion
spec:
  completions: 10
  template:
    metadata:
      labels:
        myJob: SleeperCompletion
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
kubectl apply -f job-completion.yaml
```



```bash
# Dê o seguinte comando para visualizar os jobs sendo concluídos.
# Repita até todos terem terminado:
kubectl get pods -l myJob=SleeperCompletion
```

<pre><i>
sleep-completion-95mph   0/1     Completed   0          21s
sleep-completion-mmfdt   1/1     Running     0          6s
</i></pre>

Note que os pods vão sendo criados conforme o job do pod anterior ter sido concluído.



```bash
# 
kubectl get jobs -l myJob=SleeperCompletion
```

<pre><i>
NAME               COMPLETIONS   DURATION   AGE
sleep-completion   10/10         2m33s      3m54s
</i></pre>



```bash
# 
kubectl delete -f job-completion.yaml
```



### Parallelism


```bash
# 
vim job-parallelism.yaml
```

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: sleep-parallelism
  labels:
    myJob: SleeperParallelism
spec:
  parallelism: 10
  template:
    metadata:
      labels:
        myJob: SleeperParallelism
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
kubectl apply -f job-parallelism.yaml
```



```bash
# Verificar os pods desse job:
kubectl get pods -l myJob=SleeperParallelism
```

<pre><i>
NAME                      READY   STATUS              RESTARTS   AGE
sleep-parallelism-cdc9m   0/1     ContainerCreating   0          8s
sleep-parallelism-ch6r5   0/1     ContainerCreating   0          8s
sleep-parallelism-fk25j   0/1     ContainerCreating   0          8s
sleep-parallelism-hwnqz   0/1     ContainerCreating   0          8s
sleep-parallelism-jltnr   0/1     ContainerCreating   0          8s
sleep-parallelism-mvgmc   1/1     Running             0          8s
sleep-parallelism-p7hvm   1/1     Running             0          8s
sleep-parallelism-qd2j2   0/1     ContainerCreating   0          8s
sleep-parallelism-w4kq8   0/1     ContainerCreating   0          8s
sleep-parallelism-zpzm6   0/1     ContainerCreating   0          8s
</i></pre>

Diferente de completions, com parallelism os pods são criados praticamente ao
mesmo tempo de acordo com a quantidade especificada e todos são executados
simultaneamente.



```bash
# 
kubectl get jobs -l myJob=SleeperParallelism
```

<pre><i>
NAME                COMPLETIONS   DURATION   AGE
sleep-parallelism   10/1 of 10    29s        47s
</i></pre>



```bash
# 
kubectl delete -f job-parallelism.yaml
```