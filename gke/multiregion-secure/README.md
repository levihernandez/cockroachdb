# GCP - GKE Multiregion CRDB Secured Cluster

* The Ruby script execution:
  * Uses the `config.yaml` file to populate the scripts, YAML, and Markdown files.
  * Downloads the CRDB Config scripts
  * Creates the Load Balancer & SSD Storage Manifest files
  * Configures the StatefulSet YAML (manual adjustment needed)
  * Configures the Python scripts `setup.py` & `teardown.py` 
  * Prebuilds the `gcloud`, `kubectl`, `cockroach` commands
  * Creates a Markdown file with the flow of the commands as a runbook
* Execute script:
  * `ruby prep-yaml.rb; ruby gcp.rb`
  * [Sample Markdown Runbook](sample_runbook.md)
