# RBAC

Role-Based Access Control (RBAC) is a method of regulating access to computer or network resources based on the roles of individual users within your organization.

RBAC authorization uses the rbac.authorization.k8s.io API group to drive authorization decisions, allowing you to dynamically configure policies through the Kubernetes API.



```bash
# 
kubectl create serviceaccount vivaldi
```



```bash
# 
kubectl create clusterrolebinding toskeria --serviceaccount=default:vivaldi --clusterrole=cluster-admin
```



```bash
# 
vim admin-user.yaml
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
```



```bash
# 
vim admin-cluster-role-binding.yaml
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kube-system
```



```bash
# 
kubectl apply -f admin-user.yaml
```



```bash
# 
kubectl apply -f admin-cluster-role-binding.yaml
```