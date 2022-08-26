# CRDB Deployment in GCP Multiregion K8s Cluster




## Runbook 

Generated: 08/26/2022 00:29:15



### Prebuild Commands for `gcloud`, `kubectl`, and `cockroach`

* Get local env information

```
julian@exampledomain.com

julian

jlevi-crdb-1

us-east1-b

us-east1

```

* Create a GCE Firewall Network to allow traffic on the CRDB DB port (26257)

```
gcloud compute firewall-rules create allow-cockroach-internal --allow=tcp:26257 --source-ranges=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
```

* Create a Load Balancer for the K8s cluster

```
kubectl create -f cockroachdb-lb.yaml


```

* Create the Kubernetes clusters:

```
gcloud container clusters create cockroachdb1 --region=us-east4 --machine-type= --num-nodes=3 --cluster-ipv4-cidr=10.1.0.0/16 --node-locations=us-east4-a,us-east5-a,northamerica-northeast1-a

gcloud container clusters create cockroachdb1 --region=us-east5 --machine-type= --num-nodes=3 --cluster-ipv4-cidr=10.2.0.0/16 --node-locations=us-east4-a,us-east5-a,northamerica-northeast1-a

gcloud container clusters create cockroachdb1 --region=northamerica-northeast1 --machine-type= --num-nodes=3 --cluster-ipv4-cidr=10.3.0.0/16 --node-locations=us-east4-a,us-east5-a,northamerica-northeast1-a
```

* Get the kubectl "contexts" for your clusters:

```
kubectl config get-contexts
```

* Create the Cluster Role Binding for each context

```
kubectl create clusterrolebinding julian-cluster-admin-binding --clusterrole=cluster-admin --user=julian@exampledomain.com --context=gke_jlevi-crdb-onboard1_us-east4_cockroachdb1

kubectl create clusterrolebinding julian-cluster-admin-binding --clusterrole=cluster-admin --user=julian@exampledomain.com --context=gke_jlevi-crdb-onboard1_us-east5_cockroachdb2

kubectl create clusterrolebinding julian-cluster-admin-binding --clusterrole=cluster-admin --user=julian@exampledomain.com --context=gke_jlevi-crdb-onboard1_northamerica-northeast1_cockroachdb3
```

* Create the SSD Storage for each cluster

```
kubectl create -f storage-class-ssd.yaml --context gke_jlevi-crdb-onboard1_us-east4_cockroachdb1

kubectl create -f storage-class-ssd.yaml --context gke_jlevi-crdb-onboard1_us-east5_cockroachdb2

kubectl create -f storage-class-ssd.yaml --context gke_jlevi-crdb-onboard1_northamerica-northeast1_cockroachdb3
```

### Manual Verification of `setup.py`, `teardown.py`, `cockroachdb-statefulset-secure.yaml`

* Correct the `cockroachdb-statefulset-secure.yaml` file
    * Remove `|-` from the property `spec.template.spec.containers.0.resources`



    * It must look like the generated example below:

```yaml
        resources:
        requests:
            memory: 26Gi
            cpu: 7
```


* Generated `contexts` config for `setup.py` & `teardown.py`, please validate them.

```json
contexts = {
  "us-east4-a": "gke_jlevi-crdb-onboard1_northamerica-northeast1_cockroachdb3",
  "us-east5-a": "gke_jlevi-crdb-onboard1_northamerica-northeast1_cockroachdb3",
  "northamerica-northeast1-a": "gke_jlevi-crdb-onboard1_northamerica-northeast1_cockroachdb3"
}
```

* Generated  `regions` config for `setup.py`, please validate them.

```json
regions = {
  "us-east4-a": "northamerica-northeast1",
  "us-east5-a": "northamerica-northeast1",
  "northamerica-northeast1-a": "northamerica-northeast1"
}
```

### Deploy the CRDB Cluster

* Execute the setup script. **NOTE** before doing so, validate that the setup.py & statefulset yamls are properly configured.

```
cd multiregion/

python setup.py
```

### Validate Cluster Setup

* Confirm that the CockroachDB pods in each cluster say 1/1 in the READY column, indicating that they've successfully joined the cluster:

```
kubectl get pods --selector app=cockroachdb --all-namespaces --context gke_jlevi-crdb-onboard1_us-east4_cockroachdb1

kubectl get pods --selector app=cockroachdb --all-namespaces --context gke_jlevi-crdb-onboard1_us-east5_cockroachdb2

kubectl get pods --selector app=cockroachdb --all-namespaces --context gke_jlevi-crdb-onboard1_northamerica-northeast1_cockroachdb3
```

* Use the client-secure.yaml file to launch a pod and keep it running indefinitely, specifying the context of the Kubernetes cluster to run it in (select any from the pre-built list below):

```
kubectl create -f client-secure.yaml --context gke_jlevi-crdb-onboard1_us-east4_cockroachdb1

kubectl create -f client-secure.yaml --context gke_jlevi-crdb-onboard1_us-east5_cockroachdb2

kubectl create -f client-secure.yaml --context gke_jlevi-crdb-onboard1_northamerica-northeast1_cockroachdb3
```

* [CHOOSE ONE] On secure clusters, certain pages of the DB Console can only be accessed by admin users. Get a shell into the pod with the cockroach binary created earlier and start the CockroachDB built-in SQL client:

```
kubectl exec -it cockroachdb-client-secure --context gke_jlevi-crdb-onboard1_us-east4_cockroachdb1 --namespace default -- ./cockroach sql --certs-dir=/cockroach-certs --host=cockroachdb-public

kubectl exec -it cockroachdb-client-secure --context gke_jlevi-crdb-onboard1_us-east5_cockroachdb2 --namespace default -- ./cockroach sql --certs-dir=/cockroach-certs --host=cockroachdb-public

kubectl exec -it cockroachdb-client-secure --context gke_jlevi-crdb-onboard1_northamerica-northeast1_cockroachdb3 --namespace default -- ./cockroach sql --certs-dir=/cockroach-certs --host=cockroachdb-public
```

* [CHOOSE ONE] Port-forward from your local machine to a pod in one of your Kubernetes clusters:

```
kubectl port-forward cockroachdb-1 8080 --context gke_jlevi-crdb-onboard1_us-east4_cockroachdb1 --namespace default

kubectl port-forward cockroachdb-2 8080 --context gke_jlevi-crdb-onboard1_us-east5_cockroachdb2 --namespace default

kubectl port-forward cockroachdb-3 8080 --context gke_jlevi-crdb-onboard1_northamerica-northeast1_cockroachdb3 --namespace default
```

* [CHOOSE ONE] Create a user with admin privileges

```
kubectl exec -it cockroachdb-client-secure --context gke_jlevi-crdb-onboard1_us-east4_cockroachdb1 --namespace default -- ./cockroach sql --certs-dir=/cockroach-certs --host=cockroachdb-public --execute="CREATE USER roach WITH PASSWORD '<create-password>'; GRANT admin TO roach;"

kubectl exec -it cockroachdb-client-secure --context gke_jlevi-crdb-onboard1_us-east5_cockroachdb2 --namespace default -- ./cockroach sql --certs-dir=/cockroach-certs --host=cockroachdb-public --execute="CREATE USER roach WITH PASSWORD '<create-password>'; GRANT admin TO roach;"

kubectl exec -it cockroachdb-client-secure --context gke_jlevi-crdb-onboard1_northamerica-northeast1_cockroachdb3 --namespace default -- ./cockroach sql --certs-dir=/cockroach-certs --host=cockroachdb-public --execute="CREATE USER roach WITH PASSWORD '<create-password>'; GRANT admin TO roach;"
```

* [CHOOSE ONE] Update the Enterprise License

```
kubectl exec -it cockroachdb-client-secure --context gke_jlevi-crdb-onboard1_us-east4_cockroachdb1 --namespace default -- ./cockroach sql --certs-dir=/cockroach-certs --host=cockroachdb-public --execute="SET CLUSTER SETTING cluster.organization = 'jlevi-k8s-demo'; SET CLUSTER SETTING enterprise.license = 'crl-0-<request-license>';"

kubectl exec -it cockroachdb-client-secure --context gke_jlevi-crdb-onboard1_us-east5_cockroachdb2 --namespace default -- ./cockroach sql --certs-dir=/cockroach-certs --host=cockroachdb-public --execute="SET CLUSTER SETTING cluster.organization = 'jlevi-k8s-demo'; SET CLUSTER SETTING enterprise.license = 'crl-0-<request-license>';"

kubectl exec -it cockroachdb-client-secure --context gke_jlevi-crdb-onboard1_northamerica-northeast1_cockroachdb3 --namespace default -- ./cockroach sql --certs-dir=/cockroach-certs --host=cockroachdb-public --execute="SET CLUSTER SETTING cluster.organization = 'jlevi-k8s-demo'; SET CLUSTER SETTING enterprise.license = 'crl-0-<request-license>';"
```

* [CHOOSE ONE] Simulate a failure, Scale down one of the StatefulSets to zero pods .

```
kubectl scale statefulset cockroachdb --replicas=0 --context gke_jlevi-crdb-onboard1_us-east4_cockroachdb1 --namespace default

kubectl scale statefulset cockroachdb --replicas=0 --context gke_jlevi-crdb-onboard1_us-east5_cockroachdb2 --namespace default

kubectl scale statefulset cockroachdb --replicas=0 --context gke_jlevi-crdb-onboard1_northamerica-northeast1_cockroachdb3 --namespace default
```

* [CHOOSE the one you brough down] Simulate a recovery, Scale down one of the StatefulSets to 3 pods .

```
kubectl scale statefulset cockroachdb --replicas=3 --context gke_jlevi-crdb-onboard1_us-east4_cockroachdb1 --namespace default

kubectl scale statefulset cockroachdb --replicas=3 --context gke_jlevi-crdb-onboard1_us-east5_cockroachdb2 --namespace default

kubectl scale statefulset cockroachdb --replicas=3 --context gke_jlevi-crdb-onboard1_northamerica-northeast1_cockroachdb3 --namespace default
```

### Clean Up Cluster and Cloud Resources

* Teardown CRDB Resources

```
python teardown.py
```

* Remove SSD Storage

```
kubectl delete storageclass storage-class-ssd --cluster gke_jlevi-crdb-onboard1_us-east4_cockroachdb1

kubectl delete storageclass storage-class-ssd --cluster gke_jlevi-crdb-onboard1_us-east5_cockroachdb2

kubectl delete storageclass storage-class-ssd --cluster gke_jlevi-crdb-onboard1_northamerica-northeast1_cockroachdb3
```

* Delete K8s Clusters

```
kubectl delete storageclass storage-class-ssd --cluster gke_jlevi-crdb-onboard1_us-east4_cockroachdb1

kubectl delete storageclass storage-class-ssd --cluster gke_jlevi-crdb-onboard1_us-east5_cockroachdb2

kubectl delete storageclass storage-class-ssd --cluster gke_jlevi-crdb-onboard1_northamerica-northeast1_cockroachdb3
```

* Prepare the data for YCSB workloads
* Simulate YCSB workloads in a single region
    * Get data close to the region
    * Run workload
* Simulate YCSB workloads in multiple regions
    * Partition the data with ranges for each region
    * Run workload

