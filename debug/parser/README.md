# CockroachDB - Debug Nodes JSON

Graphs are generated with Matplot and the data is presented in it's raw metric form.

Prerequisites:
* Create the Python environment and activate it
```shell
python -m venv venv
source venv/bin/activate
```

* JupyterLab and other Python libraries

```shell
pip install matplotlib pandas jupyterlab
```

* Generate the debug bundle for the CockroachDB cluster and extract the zip file `nodes.json`
```
cockroach debug zip debug.zip --certs-dir=certs --host=<node-ip>:26257

```
* Validate the file location and Run the JupyterLab project
