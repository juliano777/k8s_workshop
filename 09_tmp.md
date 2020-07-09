# Job

A Job creates one or more Pods and ensures that a specified number of them successfully terminate. As pods successfully complete, the Job tracks the successful completions. When a specified number of successful completions is reached, the task (ie, Job) is complete. Deleting a Job will clean up the Pods it created.

A simple case is to create one Job object in order to reliably run one Pod to completion. The Job object will start a new Pod if the first Pod fails or is deleted (for example due to a node hardware failure or a node reboot).

You can also use a Job to run multiple Pods in parallel.
Running an example Job
Here is an example Job config. It computes π to 2000 places and prints it out. It takes around 10s to complete.

<!-- https://kubernetes.io/docs/concepts/workloads/controllers/job/ -->



```bash
# 
vim sleeper.yaml
```



```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: sleep
  labels:
    myJob: Sleeper
spec:
  completions: 3
  parallelism: 5
  ttlSecondsAfterFinished: 100
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
        - "for i in `seq 0 15`; do echo $i; sleep 1; done"
      restartPolicy: Never
```



```bash
# 
kubectl apply -f sleeper.yaml
```



```bash
# 
kubectl get jobs -l myJob=Sleeper
```

<pre><i>
NAME    COMPLETIONS   DURATION   AGE
sleep   0/3           17s        17s
</i></pre>



```bash
# 
kubectl get pods -l myJob=Sleeper
```

<pre><i>
NAME          READY   STATUS    RESTARTS   AGE
sleep-ltdm9   1/1     Running   0          11s
sleep-rgx8f   1/1     Running   0          11s
sleep-z4ppc   1/1     Running   0          11s
</i></pre>



```bash
# 
kubectl logs sleep-ltdm9
```


<pre><i>
0
1
2
3

. . .
</i></pre>



```bash
# 
kubectl get pods -l myJob=Sleeper
```

<pre><i>
NAME          READY   STATUS      RESTARTS   AGE
sleep-ltdm9   0/1     Completed   0          9m38s
sleep-rgx8f   0/1     Completed   0          9m38s
sleep-z4ppc   0/1     Completed   0          9m38s
</i></pre>



```bash
# 
kubectl get jobs -l myJob=Sleeper
```

<pre><i>
NAME    COMPLETIONS   DURATION   AGE
sleep   3/3           24s        10m
</i></pre>



```bash
# 
kubectl describe jobs sleep
```

<pre><i>
Name:           sleep
Namespace:      default
Selector:       controller-uid=3c95fe5d-9534-46e7-87bc-a3e2c7661828
Labels:         myJob=Sleeper
Annotations:    Parallelism:  5
Completions:    3
Start Time:     Thu, 09 Jul 2020 10:24:57 -0300
Completed At:   Thu, 09 Jul 2020 10:25:21 -0300
Duration:       24s
Pods Statuses:  0 Running / 3 Succeeded / 0 Failed
Pod Template:
  Labels:  controller-uid=3c95fe5d-9534-46e7-87bc-a3e2c7661828
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
  Normal  SuccessfulCreate  57m   job-controller  Created pod: sleep-rgx8f
  Normal  SuccessfulCreate  57m   job-controller  Created pod: sleep-ltdm9
  Normal  SuccessfulCreate  57m   job-controller  Created pod: sleep-z4ppc
  Normal  Completed         56m   job-controller  Job completed
</i></pre>