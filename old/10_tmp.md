# CronJob

Um Cron Job cria Jobs em um cronograma baseado em tempo.

Um objeto CronJob é como um arquivo crontab (tabela cron). Executa um job periodicamente em um determinado horário, escrito no formato Cron.

You can use a CronJob to run Jobs on a time-based schedule. These automated jobs run like Cron tasks on a Linux or UNIX system.

Cron jobs are useful for creating periodic and recurring tasks, like running backups or sending emails. Cron jobs can also schedule individual tasks for a specific time, such as if you want to schedule a job for a low activity period.

Cron jobs have limitations and idiosyncrasies. For example, in certain circumstances, a single cron job can create multiple jobs. Therefore, jobs should be idempotent.



```bash
# 
vim cronjob-01.yaml
```



```yaml
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: cronjob-01
spec:
  schedule: "*/1 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: cronjob-01
            image: alpine
            args:
            - /bin/sh
            - -c
            - date +%Y%m%d;echo 'Heavy Metal never die!!!';sleep 10
          restartPolicy: OnFailure
```



```bash
# 
kubectl apply -f cronjob-01.yaml
```



```bash
# 
kubectl get cronjobs
```

<pre><i>
NAME         SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob-01   */1 * * * *   False     0        <none>          21s
</i></pre>



```bash
# 
kubectl describe cronjobs.batch cronjob-01
```

. . .



```bash
# 
kubectl get jobs --watch
```

<pre><i>
NAME                    COMPLETIONS   DURATION   AGE
cronjob-01-1596320700   0/1                      0s
cronjob-01-1596320700   0/1           0s         0s
cronjob-01-1596320700   1/1           15s        15s
cronjob-01-1596320760   0/1                      0s
cronjob-01-1596320760   0/1           0s         0s
</i></pre>



```bash
# 
kubectl get cronjob cronjob-01
```

<pre><i>
NAME         SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob-01   */1 * * * *   False     0        43s             3m25s
</i></pre>



```bash
# 
kubectl get pods
```

<pre><i>
NAME                          READY   STATUS      RESTARTS   AGE
cronjob-01-1596320700-2wrnn   0/1     Completed   0          3m12s
cronjob-01-1596320760-2ltlf   0/1     Completed   0          2m12s
cronjob-01-1596320820-j8qkt   0/1     Completed   0          72s
cronjob-01-1596320880-jz6nw   1/1     Running     0          12s
</i></pre>



```bash
# 
kubectl  logs cronjob-01-1596320880-jz6nw
```

<pre><i>
20200801
Heavy Metal never die!!!
</i></pre>



```bash
# 
kubectl delete cronjob cronjob-01
```