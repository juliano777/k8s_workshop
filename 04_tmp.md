# Labels

Labels are key/value pairs that are attached to objects, such as pods. Labels are intended to be used to specify identifying attributes of objects that are meaningful and relevant to users, but do not directly imply semantics to the core system. Labels can be used to organize and to select subsets of objects. Labels can be attached to objects at creation time and subsequently added and modified at any time. Each object can have a set of key/value labels defined. Each Key must be unique for a given object.

## Motivação

Labels enable users to map their own organizational structures onto system objects in a loosely coupled fashion, without requiring clients to store these mappings.

Service deployments and batch processing pipelines are often multi-dimensional entities (e.g., multiple partitions or deployments, multiple release tracks, multiple tiers, multiple micro-services per tier). Management often requires cross-cutting operations, which breaks encapsulation of strictly hierarchical representations, especially rigid hierarchies determined by the infrastructure rather than by users.



```bash
# Listando pods cujo label atenda a seguinte combinação de chave e valor:
kubectl get pods -l color=Green
```

<pre><i>
NAME                        READY   STATUS    RESTARTS   AGE
deploy01-5fd6dcb8d8-tkvq9   1/1     Running   0          25m
</i></pre>




```bash
# Listando pods que tenham uma label com a chave color:
kubectl get pod -L color
```

<pre><i>
NAME                        READY   STATUS    RESTARTS   AGE   COLOR
deploy01-5fd6dcb8d8-tkvq9   1/1     Running   0          25m   Green
deploy02-5dc8f99fdf-s6p8s   1/1     Running   0          19m   Orange
</i></pre>