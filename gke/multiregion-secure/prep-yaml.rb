require 'yaml'
require 'fileutils'

=begin
Read a single YAML file containing multiple YAMLs and replace YAML values for a specific property

- Load config YAML
- Load YAML to modify (iteration)
  - For each internal file replace the YAML property
  - Write independent files to a temp dir
  - Store new independent file names to an array for future reference
- Use the array containing the independent files
    - Loop through each name, read the temp independent YAML, and append them to a single YAML file
- Remove the temp dir containing the independent YAMLs
=end


# Load the main config yaml
ymlcnf = YAML.load_file('config.yaml')
# get data and store into vars
storage = ymlcnf["cloud"]["storage"]
storagetype = ymlcnf["cloud"]["storagetype"]
nodespeccpu = ymlcnf["cloud"]["noderesourcescpu"]
nodespecmem = ymlcnf["cloud"]["noderesourcesmem"]
crdbuiport = ymlcnf["crdb"]["uiport"]
crdbportdb = ymlcnf["crdb"]["dbport"]

# Stackoverflow example of a YAML single file update:
#data = YAML::load(File.open(File.expand_path("../../../data/test.yml", __FILE__)))
#data["test"]["accounts"]["id"] = 2
#File.open((File.expand_path("../../../data/"test.yml", __FILE__)), 'w') {|f| f.write data.to_yaml } 


## Create a while loop to store yaml files separately and in different variables
# while read file, create dictionary var, store loaded file, reference file externally if possible
yamls = []
tmpdir = "tmp"
mrdir = "multiregion"
mrdowndir = "#{mrdir}_download"
tmpl = "crdb-multiregion-runbook-tmpl.md"
runb = "crdb-multiregion-runbook.md"




## Functions that prep data for the gcloud/kubectl commands and other prep work
def download_mr_files(mrdowndir, mrdir)
    downfiles = ["README.md","client-secure.yaml","cluster-init-secure.yaml","cockroachdb-statefulset-secure.yaml","dns-lb.yaml","example-app-secure.yaml","external-name-svc.yaml","setup.py","teardown.py"]
    for d in downfiles do
        Down.download("https://raw.githubusercontent.com/cockroachdb/cockroach/master/cloud/kubernetes/#{mrdir}/#{d}", destination: "./#{mrdowndir}/#{d}")
    end
end

## Create directories 
Dir.exist?(mrdir)
Dir.exist?(mrdowndir)
Dir.mkdir(tmpdir) unless File.exists?(tmpdir)

## Download the K8s Secure Multi-region cluster config and scripts
if Dir.empty?(mrdowndir)
    puts "Downloading CRDB Config Setup Files...\n\n"
    download_mr_files(mrdowndir, mrdir)
else
    puts "CRDB Config Setup Files already downloaded...\n\n"
end

# Create the Markdown copy
FileUtils.cp_r "#{tmpl}", "#{runb}"
FileUtils.cp_r "#{mrdowndir}/.", "#{mrdir}/"

def overwrite_markdown(tmpl, data, pattern)
    text = [] 
    data.map{|key, value| text.append("#{value}\n\n")}
    output = text.join("")
    original = File.read(tmpl)
    changes = original.gsub(pattern, output)
    File.open(tmpl, "w") {|file| file.puts changes }
    puts "-----------------"
    puts output
end

# Replace properties in the StatefulSet YAML
YAML.load_stream(File.read("#{mrdowndir}/cockroachdb-statefulset-secure.yaml")) do |document|
    # For each  file, append to dictionary variable
    kind = document["kind"]
    meta = document["metadata"]["name"]
    # puts "YAML File: #{kind} -> #{meta}\n"
    if kind === "StatefulSet" and meta === "cockroachdb"
        #storageyml = document["spec"]["volumeClaimTemplates"][0]["spec"]["resources"]["requests"]["storage"]
        puts "Updating YAML StatefulSet...\n\n"

        # TODO: Find a way to insert nested YAML
        #document["spec"]["template"]["spec"]["containers"][0]["resources"] = nodespeccpu
        #document["spec"]["template"]["spec"]["containers"][0]["resources"]["requests"]["memory"] = nodespecmem
        
        chng = "Remove `|-` from the property `spec.template.spec.containers.0.resources`\n"
        # Document in the markdown the manual changes to statefulset
        pattern = "{{ ss-correction }}"
        data = {"change":chng }
        overwrite_markdown(tmpl, data, pattern)
        pattern = "{{ sample-resource-requests }}"
        ymsample = "        resources:
        requests:
            memory: 26Gi
            cpu: 7"
        data = {"change":ymsample }
        overwrite_markdown(tmpl, data, pattern)

        document["spec"]["template"]["spec"]["containers"][0]["resources"] = "requests:\n    memory: #{nodespecmem}\n    cpu: #{nodespeccpu}"
        document["spec"]["volumeClaimTemplates"][0]["spec"]["storageClassName"] = storagetype
        document["spec"]["volumeClaimTemplates"][0]["spec"]["resources"]["requests"]["storage"] = storage

        puts "YAML StatefulSet is configured, validate the settings..."
    end
    # Append file names to array in order to merge them in order
    yamls.append("#{tmpdir}/cockroachdb-statefulset-secure_#{kind}-#{meta}.yaml")
    # Create individual files
    File.open("#{tmpdir}/cockroachdb-statefulset-secure_#{kind}-#{meta}.yaml", 'w') {|f| f.write document.to_yaml } 
end

# Remove special char in StatefulSet config

# Merge ALL temp YAML files into a single YAML file
ssfile = "./#{mrdir}/cockroachdb-statefulset-secure.yaml"
File.truncate(ssfile, 0)
f = File.open(ssfile, 'a')
for y in yamls
  puts "merging #{y}"
  # File.write('some-file.txt', 'here is some text', File.size('some-file.txt'), mode: 'a')
  r = File.read(y)
  f.write(r)  
end
f.close

# Clean up the tmp dir containing the temp config yaml files
FileUtils.rm_rf(tmpdir)

# Create the Load Balancer YAML config
f = File.open('storage-class-ssd.yaml', 'w')
data = "apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: storage-class-ssd
provisioner: kubernetes.io/gce-pd
parameters:
  type: pd-ssd"
f.write(data)
f.close

# Create the Storage SSD YAML config
f = File.open('cockroachdb-lb.yaml', 'w')
data = "apiVersion: v1
kind: Service
metadata:
  name: crdb-lb
  labels:
    app: cockroachdb
spec:
  selector:
    app.kubernetes.io/name: cockroachdb
  ports:
  - protocol: \"TCP\"
    port: #{crdbuiport}
    name: dbconsole
  - protocol: \"TCP\"
    port: #{crdbportdb}
    name: sql
  type: LoadBalancer"
f.write(data)
f.close
