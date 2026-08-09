# Helm

Helm helps you manage Kubernetes applications — Helm Charts help you define, install, and upgrade even the most complex Kubernetes application.

Charts are easy to create, version, share, and publish — so start using Helm and stop the copy-and-paste.



```bash
# 
wget https://storage.googleapis.com/kubernetes-helm/helm-v2.12.3-linux-amd64.tar.gz
```



```bash
# 
tar -vxzf helm-v2.11.0-linux-amd64.tar.gz
```



```bash
# 
cd linux-amd64/
```



```bash
# 
mv helm /usr/local/bin/
```



```bash
# 
mv tiller /usr/local/bin/
```



```bash
# 
helm init
```



```bash
# 
kubectl create serviceaccount --namespace=kube-system tiller
```



```bash
# 
kubectl create clusterrolebinding tiller-cluster-role --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
```



```bash
# 
kubectl patch deployments -n kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'
```



```bash
# 
helm install --namespace=monitoring --name=prometheus --version=7.0.0 --set alertmanager.persistentVolume.enabled=false,server.persistentVolume.enabled=false stable/prometheus
```



```bash
# 
helm list
```

<pre><i>

</i></pre>



```bash
# 
helm search grafana
```

<pre><i>

</i></pre>



```bash
# 
helm install --namespace=monitoring --name=grafana --version=1.12.0 --set=adminUser=admin,adminPassword=admin,service.type=NodePort stable/grafana
```



```bash
# 
helm list
```

<pre><i>

</i></pre>



```bash
# 
kubectl  get deployments.
```

<pre><i>

</i></pre>



```bash
# 
kubectl  get service
```

<pre><i>

</i></pre>



```bash
# 
helm delete prometheus
```



```bash
# 
helm delete grafana
```



```bash
# 
helm list
```

<pre><i>

</i></pre>



```bash
# 
helm reset
```