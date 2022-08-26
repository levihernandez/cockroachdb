# {{ title }}


## Runbook 

Generated: {{ timestamp }}

### Prebuild Commands for `gcloud`, `kubectl`, and `cockroach`

* Get local env information

```
{{ local-gcloud-env }}
```

* Create a GCE Firewall Network to allow traffic on the CRDB DB port (26257)

```
{{ gce-firewall }}
```

* Create a Load Balancer for the K8s cluster

```
{{ gke-lb }}
```

* Create the Kubernetes clusters:

```
{{ create-k8s-cluster }}
```

* Get the kubectl "contexts" for your clusters:

```
{{ get-k8s-context }}
```

* Create the Cluster Role Binding for each context

```
{{ create-clusterrolebinding }}
```

* Create the SSD Storage for each cluster

```
{{ create-ssd-storage }}
```

### Manual Verification of `setup.py`, `teardown.py`, `cockroachdb-statefulset-secure.yaml`

* Correct the `cockroachdb-statefulset-secure.yaml` file
    * Review the property `spec.template.spec.containers.0.resources.requests` cpu & memory 
    * The syntax must look like the example below:

```yaml
        resources:
          requests:
            cpu: "3500m"
            memory: "12300Mi"
          limits:
            cpu: "3500m"
            memory: "12300Mi"
```


* Generated `contexts` config for `setup.py` & `teardown.py`, please validate them.

```json
{{ json-contexts }}
```

* Generated  `regions` config for `setup.py`, please validate them.

```json
{{ json-regions }}
```

### Deploy the CRDB Cluster

* Execute the setup script. **NOTE** before doing so, validate that the setup.py & statefulset yamls are properly configured.

```
{{ change-dir }}
{{ run-setup-script }}
```

### Validate Cluster Setup

* Confirm that the CockroachDB pods in each cluster say 1/1 in the READY column, indicating that they've successfully joined the cluster:

```
{{ get-pods }}
```

* Use the client-secure.yaml file to launch a pod and keep it running indefinitely, specifying the context of the Kubernetes cluster to run it in (select any from the pre-built list below):

```
{{ client-secure }}
```

* [CHOOSE ONE] On secure clusters, certain pages of the DB Console can only be accessed by admin users. Get a shell into the pod with the cockroach binary created earlier and start the CockroachDB built-in SQL client:

```
{{ access-db-console }}
```

* [CHOOSE ONE] Port-forward from your local machine to a pod in one of your Kubernetes clusters:

```
{{ port-forward }}
```

* [CHOOSE ONE] Create a user with admin privileges

```
{{ dba }}
```

* [CHOOSE ONE] Update the Enterprise License

```
{{ enterprise-license }}
```

* [CHOOSE ONE] Simulate a failure, Scale down one of the StatefulSets to zero pods .

```
{{ scale-down }}
```

* [CHOOSE the one you brough down] Simulate a recovery, Scale down one of the StatefulSets to 3 pods .

```
{{ scale-up }}
```

### Clean Up Cluster and Cloud Resources

* Teardown CRDB Resources

```
{{ teardown-crdb }}
```

* Remove SSD Storage

```
{{ delete-ssd-storage }}
```

* Delete K8s Clusters

```
{{ delete-k8s-cluster }}
```

* Delete GPC VPC Firewall

```
{{ gce-delete-firewall }}
```

* Prepare the data for YCSB workloads
* Simulate YCSB workloads in a single region
    * Get data close to the region
    * Run workload
* Simulate YCSB workloads in multiple regions
    * Partition the data with ranges for each region
    * Run workload

