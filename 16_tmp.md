# Ingress

An API object that manages external access to the services in a cluster, typically HTTP.

Ingress may provide load balancing, SSL termination and name-based virtual hosting.

Terminology

For clarity, this guide defines the following terms:

    Node: A worker machine in Kubernetes, part of a cluster.
    Cluster: A set of Nodes that run containerized applications managed by Kubernetes. For this example, and in most common Kubernetes deployments, nodes in the cluster are not part of the public internet.
    Edge router: A router that enforces the firewall policy for your cluster. This could be a gateway managed by a cloud provider or a physical piece of hardware.
    Cluster network: A set of links, logical or physical, that facilitate communication within a cluster according to the Kubernetes networking model.
    Service: A Kubernetes Service that identifies a set of Pods using label selectors. Unless mentioned otherwise, Services are assumed to have virtual IPs only routable within the cluster network.

What is Ingress?

Ingress exposes HTTP and HTTPS routes from outside the cluster to services within the cluster. Traffic routing is controlled by rules defined on the Ingress resource.

    internet
        |
   [ Ingress ]
   --|-----|--
   [ Services ]

An Ingress may be configured to give Services externally-reachable URLs, load balance traffic, terminate SSL / TLS, and offer name based virtual hosting. An Ingress con

troller is responsible for fulfilling the Ingress, usually with a load balancer, though it may also configure your edge router or additional frontends to help handle the traffic.

An Ingress does not expose arbitrary ports or protocols. Exposing services other than HTTP and HTTPS to the internet typically uses a service of type Service.Type=NodePort or Service.Type=LoadBalancer.

# =============================================================================================



```bash
# 
vim app1.yaml
```

```yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: app1
spec:
  replicas: 2
  template:
    metadata:
      labels:
        app: app1
    spec:
      containers:
      - name: app1
        image: dockersamples/static-site
        env:
        - name: AUTHOR
          value: GIROPOPS
        ports:
        - containerPort: 80
```


```bash
# 
vim svc-app1.yaml
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: appsvc1
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: app1
```




```bash
# 
vim svc-app2.yaml
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: appsvc2
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: app2
```



```bash
# 
kubectl apply -f app1.yaml
```



```bash
# 
kubectl apply -f app2.yaml
```



```bash
# 
kubectl apply -f svc-app1.yaml
```



```bash
# 
kubectl apply -f svc-app2.yaml
```



```bash
# 
kubectl get deploy
```

<pre><i>

</i></pre>



```bash
# 
kubectl get services
```

<pre><i>

</i></pre>



```bash
# 
kubectl get ep
```

<pre><i>

</i></pre>



```bash
# 
vim default-backend.yaml
```

```yaml

```



```bash
# 
kubectl create namespace ingress
```



```bash
# 
kubectl create -f default-backend.yaml -n ingress
```



```bash
# 
vim default-backend-service.yaml
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: default-backend
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 8080
  selector:
    app: default-backend
```



```bash
# 
kubectl create -f default-backend-service.yaml -n ingress
```



```bash
# 
kubectl get deployments
```

<pre><i>

</i></pre>



```bash
# 
kubectl get deployments. -n ingress
```

<pre><i>

</i></pre>



```bash
# 
kubectl get service
```

<pre><i>

</i></pre>



```bash
# 
kubectl get service -n ingress
```

<pre><i>

</i></pre>



```bash
# 
kubectl get ep -n ingress
```

<pre><i>

</i></pre>



```bash
# 
vim nginx-ingress-controller-config-map.yaml
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-ingress-controller-conf
  labels:
    app: nginx-ingress-lb
data:
  enable-vts-status: 'true'
```



```bash
# 
kubectl create -f nginx-ingress-controller-config-map.yaml -n ingress
```



```bash
# 
kubectl describe configmaps nginx-ingress-controller-conf -n ingress
```

<pre><i>

</i></pre>



```bash
# 
kubectl get configmaps -n ingress
```

<pre><i>

</i></pre>



```bash
# 
vim nginx-ingress-controller-roles.yaml
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nginx
  namespace: ingress
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: nginx-role
rules:
- apiGroups:
  - ""
  - "extensions"
  resources:
  - configmaps
  - secrets
  - endpoints
  - ingresses
  - nodes
  - pods
  verbs:
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - services
  verbs:
  - list
  - watch
  - get
  - update
- apiGroups:
  - "extensions"
  resources:
  - ingresses
  verbs:
  - get
- apiGroups:
  - ""
  resources:
  - events
  verbs:
  - create
- apiGroups:
  - "extensions"
  resources:
  - ingresses/status
  verbs:
  - update
- apiGroups:
  - ""
  resources:
  - configmaps
  verbs:
  - get
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: nginx-role
  namespace: ingress
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: nginx-role
subjects:
- kind: ServiceAccount
  name: nginx
  namespace: ingress
```



```bash
# 
kubectl create -f nginx-ingress-controller-roles.yaml -n ingress
```



```bash
# 
kubectl get serviceaccounts
```

<pre><i>

</i></pre>



```bash
# 
kubectl get clusterrole -n ingress
```

<pre><i>

</i></pre>



```bash
# 
kubectl get clusterrolebindings -n ingress
```

<pre><i>

</i></pre>



```bash
# 
vim nginx-ingress-controller-deployment.yaml
```

```yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: nginx-ingress-controller
spec:
  replicas: 1
  revisionHistoryLimit: 3
  template:
    metadata:
      labels:
        app: nginx-ingress-lb
    spec:
      terminationGracePeriodSeconds: 60
      serviceAccount: nginx
      containers:
        - name: nginx-ingress-controller
          image: quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.9.0
          imagePullPolicy: Always
          readinessProbe:
            httpGet:
              path: /healthz
              port: 10254
              scheme: HTTP
          livenessProbe:
            httpGet:
              path: /healthz
              port: 10254
              scheme: HTTP
            initialDelaySeconds: 10
            timeoutSeconds: 5
          args:
            - /nginx-ingress-controller
            - --default-backend-service=ingress/default-backend
            - --configmap=ingress/nginx-ingress-controller-conf
            - --v=2
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
          ports:
            - containerPort: 80
            - containerPort: 18080
```



```bash
# 
kubectl create -f nginx-ingress-controller-deployment.yaml -n ingress
```



```bash
# 
kubectl get deployments -n ingress
```

<pre><i>

</i></pre>



```bash
# 
kubectl get pods --all-namespaces
```

<pre><i>

</i></pre>



```bash
# 
vim nginx-ingress.yaml
```

```yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: nginx-ingress
spec:
  rules:
  - host: ec2-54-198-119-88.compute-1.amazonaws.com # Mude para o seu endereço
    http:
      paths:
      - backend:
          serviceName: nginx-ingress
          servicePort: 18080
        path: /nginx_status
```



```bash
# 
vim app-ingress.yaml
```

```yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
  name: app-ingress
spec:
  rules:
  - host: ec2-54-198-119-88.compute-1.amazonaws.com # Mude para o seu endereço
    http:
      paths:
      - backend:
          serviceName: appsvc1
          servicePort: 80
        path: /app1
      - backend:
          serviceName: appsvc2
          servicePort: 80
        path: /app2
```



```bash
# 
kubectl create -f nginx-ingress.yaml -n ingress
```



```bash
# 
kubectl create -f app-ingress.yaml
```



```bash
# 
kubectl get ingresses
```

<pre><i>

</i></pre>



```bash
# 
kubectl get ingresses -n ingress
```

<pre><i>

</i></pre>



```bash
# 
kubectl describe ingresses.extensions nginx-ingress -n ingress
```

<pre><i>

</i></pre>



```bash
# 
kubectl describe ingresses.extensions app-ingress
```

<pre><i>

</i></pre>


```bash
# 
vim nginx-ingress-controller-service.yaml
```

```yaml

```



```bash
# 
kubectl create -f nginx-ingress-controller-service.yaml -n=ingress
```



<!--
Pronto, agora você já pode acessar suas apps pela URL que você configurou. Abra o navegador e adicione os seguintes endereços:

http://SEU-ENDEREÇO:30000/app1

http://SEU-ENDEREÇO:30000/app2

http://SEU-ENDEREÇO:32000/nginx_status

Ou ainda via curl:

curl http://SEU-ENDEREÇO:30000/app1


curl http://SEU-ENDEREÇO:30000/app2


curl http://SEU-ENDEREÇO:32000/nginx_status

-->



```bash
# 
curl http://SEU-ENDEREÇO:30000/app1
```



```bash
# 
curl http://SEU-ENDEREÇO:30000/app2
```



```bash
# 
curl http://SEU-ENDEREÇO:32000/nginx_status
```


