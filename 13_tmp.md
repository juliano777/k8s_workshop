# initContainer

This page provides an overview of init containers: specialized containers that run before app containers in a Pod . Init containers can contain utilities or setup scripts not present in an app image.

You can specify init containers in the Pod specification alongside the containers array (which describes app containers).
Understanding init containers

A Pod can have multiple containers running apps within it, but it can also have one or more init containers, which are run before the app containers are started.

Init containers are exactly like regular containers, except:

    Init containers always run to completion.
    Each init container must complete successfully before the next one starts.

If a Pod's init container fails, Kubernetes repeatedly restarts the Pod until the init container succeeds. However, if the Pod has a restartPolicy of Never, Kubernetes does not restart the Pod.

To specify an init container for a Pod, add the initContainers field into the Pod specification, as an array of objects of type Container, alongside the app containers array. The status of the init containers is returned in .status.initContainerStatuses field as an array of the container statuses (similar to the .status.containerStatuses field).
Differences from regular containers

Init containers support all the fields and features of app containers, including resource limits, volumes, and security settings. However, the resource requests and limits for an init container are handled differently, as documented in Resources.

Also, init containers do not support lifecycle, livenessProbe, readinessProbe, or startupProbe because they must run to completion before the Pod can be ready.

If you specify multiple init containers for a Pod, Kubelet runs each init container sequentially. Each init container must succeed before the next can run. When all of the init containers have run to completion, Kubelet initializes the application containers for the Pod and runs them as usual.

Using init containers

Because init containers have separate images from app containers, they have some advantages for start-up related code:

    Init containers can contain utilities or custom code for setup that are not present in an app image. For example, there is no need to make an image FROM another image just to use a tool like sed, awk, python, or dig during setup.
    The application image builder and deployer roles can work independently without the need to jointly build a single app image.
    Init containers can run with a different view of the filesystem than app containers in the same Pod. Consequently, they can be given access to Secrets that app containers cannot access.
    Because init containers run to completion before any app containers start, init containers offer a mechanism to block or delay app container startup until a set of preconditions are met. Once preconditions are met, all of the app containers in a Pod can start in parallel.
    Init containers can securely run utilities or custom code that would otherwise make an app container image less secure. By keeping unnecessary tools separate you can limit the attack surface of your app container image.


```bash
# 
vim initcontainer-01.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-www
spec:
  containers:
  - name: www
    image: nginx
    ports:
    - containerPort: 80
    volumeMounts:
    - name: www-dir
      mountPath: /usr/share/nginx/html
  initContainers:
  - name: racer-x
    image: busybox
    command:
    - 'wget'
    - '-O'
    - '/zero/index.html'
    - 'http://kubernetes.io'
    volumeMounts:
    - name: www-dir
      mountPath: '/zero'
  dnsPolicy: Default
  volumes:
  - name: www-dir
    emptyDir: {}
```



```bash
# 
kubectl apply -f initcontainer-01.yaml
```



```bash
# 
kubectl exec -ti init-zero -- cat /usr/share/nginx/html/index.html
```



```bash
# 
kubectl describe pod init-zero
```

<pre><i>

</i></pre>



```bash
# Caso houver erro por conta de acesso à internet, dê o seguinte comando:
sudo iptables -P FORWARD ACCEPT
```



