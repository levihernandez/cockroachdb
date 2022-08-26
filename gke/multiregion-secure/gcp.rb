require 'yaml'
require 'json'
require 'down'
require 'fileutils'


=begin
The following script is writen to facilitate a markdown runbook for a quick deployment
of K8s secure in a multi-region setup in GCP.


- Read config yaml
- Download CRDB Config Setup Files
- prebuild gconsole commands to deploy
    - multi-region K8s cluster
    - cluster binding roles
    - nodes
    - contexts
    - multi-region cluster deployment security
- Overwrite config files with new changes
- Simulate the crash of a region
- Restablish the region
- TODO: Test workload with YCSB
    - Single-region test
    - Multi-region test
    - Save benchmarks & cluster performance metrics
=end

## Review the gcloud info values: 
# gcloud info --format flattened
account = `gcloud info --format="value(config.account.scope())"`.gsub(/\n/,"")
project = `gcloud info --format="value(config.project.scope())"`.gsub(/\n/,"")
regionnow = `gcloud info --format="value(config.properties.compute.region.value.scope())"`
zonenow = `gcloud info --format="value(config.properties.compute.zone.value.scope())"`
userid = account.split('@',2).first
conf = "config.yaml"
runbook = "#{userid}-GCP-MR-deployment.md"

## Read config and populate vars
ymlcnf = YAML.load_file('config.yaml')
cloud = ymlcnf["cloud"]["cloud"]
mrdir = "multiregion"
mrdowndir = "#{mrdir}_download"

k8snumnodes = ymlcnf["cloud"]["node"]
k8sazs = ymlcnf["cloud"]["compute"]
# k8sregions = ymlcnf["cloud"]
k8snamespace = ymlcnf["cloud"]["namespace"]
k8svmtype = ymlcnf["cloud"]["vm-type"]
ipsrcranges = ymlcnf["cloud"]["vpcipsrcrange"]

nodereplica = ymlcnf["cloud"]["replicas"]
nodecount = ymlcnf["cloud"]["nodes"]
nodestorage = ymlcnf["cloud"]["storage"] 
nodespeccpu = ymlcnf["cloud"]["noderesourcescpu"]
nodespecmem = ymlcnf["cloud"]["noderesourcesmem"]

## CRDB config settings
crdbentlic = ymlcnf["crdb"]["enterpricelicense"]
crdborgid  = ymlcnf["crdb"]["orgid"]
crdbuiuser = ymlcnf["crdb"]["uiuser"]
crdbuipass = ymlcnf["crdb"]["uipass"]
crdbuiport = ymlcnf["crdb"]["uiport"]
crdbportdb = ymlcnf["crdb"]["dbport"]


## Runbook Template File
tmpl = "crdb-multiregion-runbook.md"

## Functions that prep data for the gcloud/kubectl commands and other prep work
def download_mr_files(mrdowndir, mrdir)
    downfiles = ["README.md","client-secure.yaml","cluster-init-secure.yaml","cockroachdb-statefulset-secure.yaml","dns-lb.yaml","example-app-secure.yaml","external-name-svc.yaml","setup.py","teardown.py"]
    for d in downfiles do
        Down.download("https://raw.githubusercontent.com/cockroachdb/cockroach/master/cloud/kubernetes/#{mrdir}/#{d}", destination: "./#{mrdowndir}/#{d}")
    end
end

## Create directories 
Dir.mkdir(mrdir) unless File.exists?(mrdir)
Dir.mkdir(mrdowndir) unless File.exists?(mrdowndir)

## Download the K8s Secure Multi-region cluster config and scripts
if Dir.empty?(mrdowndir)
    puts "Downloading CRDB Config Setup Files...\n\n"
    download_mr_files(mrdowndir, mrdir)
else
    puts "CRDB Config Setup Files already downloaded...\n\n"
end

## Current dir: File.basename(Dir.getwd)
## Copy contents from downloaded to the final version dir
puts "Copying downloaded CRDB Config Setup Files to #{mrdir} dir... overwriting files now!\n\n"
FileUtils.cp_r "#{mrdowndir}/.", "#{mrdir}/"

def get_all_azs(k8sazs)
    # Get an array of only the AZ for each region
    az_arr = []
    for az in k8sazs do
        for a in az["az"] do
            az_arr.append(a)
        end
    end
    return az_arr
end

def build_commands(cmds, data)
    case cmds
        when "cd-dir"
            ## command cd - done
            cmd = "cd #{data[:mrdir]}/"
        when "create-k8s-lb"
            ## command lb - done
            cmd = "kubectl create -f cockroachdb-lb.yaml"
        when "create-compute-firewall"
            ## command fw -
            cmd = "gcloud compute firewall-rules create allow-cockroach-internal --allow=tcp:#{data[:crdbportdb]} --source-ranges=#{data[:ipsrcranges]}"    
        when "create-ssd-storage"
            ## command ssd
            cmd = "kubectl create -f storage-class-ssd.yaml --context #{data[:context]}"
        when "run-setup-py"
            ## command py
            cmd = "python setup.py"
        when "container-clusters-create"
            ## command 1 - done
            cmd = "gcloud container clusters create cockroachdb1 --region=#{data[:region]} --machine-type=#{data[:vmtype]} --num-nodes=#{data[:nodecount]} --cluster-ipv4-cidr=#{data[:cidrip]} --node-locations=#{data[:csvzones]}"
        when "config-context"
            ## command 2 - done
            cmd = "kubectl config get-contexts"
        when "create-clusterrolebinding"
            ## command 3 - done
            cmd = "kubectl create clusterrolebinding #{data[:user]}-cluster-admin-binding --clusterrole=cluster-admin --user=#{data[:account]} --context=#{data[:context]}"
        when "get-pods-context"
            ## command 4 - done
            cmd = "kubectl get pods --selector app=cockroachdb --all-namespaces --context #{data[:context]}"
        when "create-f-client-secure"
            ## command 5 - done
            cmd = "kubectl create -f client-secure.yaml --context #{data[:context]}"
        when "exec-client-context-sql"
            ## command 6 - done
            cmd = "kubectl exec -it cockroachdb-client-secure --context #{data[:context]} --namespace #{data[:namespace]} -- ./cockroach sql --certs-dir=/cockroach-certs --host=cockroachdb-public"
        when "port-fwd-crdb"
            ## command 7 - 
            cmd = "kubectl port-forward cockroachdb-#{data[:clusternum]} #{data[:uiport]} --context #{data[:context]} --namespace #{data[:namespace]}"
        when "scale-cluster"
            ## command 8
            cmd = "kubectl scale statefulset cockroachdb --replicas=#{data[:scale]} --context #{data[:context]} --namespace #{data[:namespace]}"
        when "ycsb-single-region"
            ## command 9 - TODO
            cmd = ""
        when "ycsb-multi-region"
            ## command 10 - TODO
            cmd = ""
        when "create-db-admin"
            ## command dba - TODO
            cmd = "kubectl exec -it cockroachdb-client-secure --context #{data[:context]} --namespace #{data[:namespace]} -- ./cockroach sql --certs-dir=/cockroach-certs --host=cockroachdb-public --execute=\"CREATE USER #{data[:uiuser]} WITH PASSWORD '#{data[:uipass]}'; GRANT admin TO #{data[:uiuser]};\""
        when "apply-enterprise-license"
            ## command lic - TODO
            cmd = "kubectl exec -it cockroachdb-client-secure --context #{data[:context]} --namespace #{data[:namespace]} -- ./cockroach sql --certs-dir=/cockroach-certs --host=cockroachdb-public --execute=\"SET CLUSTER SETTING cluster.organization = '#{data[:orgid]}'; SET CLUSTER SETTING enterprise.license = '#{data[:license]}';\""    
        when "teardown-setup-py"
            ## command delrs - TODO
            cmd = "python teardown.py"
        when "delete-ssd-storage"
            ## command delssd - TODO
            cmd = "kubectl delete storageclass storage-class-ssd --cluster #{data[:context]}"
        when "delete-clusters"
            ## command delclstr- TODO
            cmd = "gcloud container clusters delete cockroachdb#{data[:clusternum]} --region=#{data[:region]} --quiet"
    end
    return cmd
end

allazs = get_all_azs(k8sazs)
allazcsv = allazs.join(',')

cmdscd = "cd-dir"
datacd = {}
datacd.merge!("mrdir": mrdir)
phcd = build_commands(cmdscd, datacd)

cmdspy = "run-setup-py"
datapy = {}
datapy.merge!("mrdir": mrdir)
phpy = build_commands(cmdspy, datapy)

cmddelrs = "teardown-setup-py"
datadelrs = {}
datadelrs.merge!("down": mrdir)
phdelrs = build_commands(cmddelrs, datadelrs)

cmdslb = "create-k8s-lb"
phlb = build_commands(cmdslb, "")

cmdscntxt = "config-context"
phcntxt = build_commands(cmdscntxt, "")

cmdsfw = "create-compute-firewall"
datafw = {}
datafw.merge!("crdbportdb": crdbportdb)
datafw.merge!("ipsrcranges": ipsrcranges)
phfw = build_commands(cmdsfw, datafw)



ph1 = {}  # Get cluster create command
ph2 = {}  # Get context command
ph3 = {}

ph4 = {}
ph5 = {}
ph6 = {}
ph7 = {}
phup = {}
phdown = {}
ph9 = {}
ph10 = {}
phssd = {}
phdelssd = {}
phdelclstr = {}
phdba = {}
phlic = {}
json_cntx = {}
json_regs = {}
## For each cluster - prebuild commands and store them in arrays or dictionaries
k8sazs.each_with_index do |k, i|
    i += 1
    crdbregion = k["region"]
    crdbzone = ""
    contextid = "gke_#{project}_#{crdbregion}_cockroachdb#{i}"
    vpccidrip = k["cidrip"]
    puts "\n\nCRDB K8s Cluster#{i} <Context#{i}>:  #{contextid}\n\n"
    

    cmds1 = "container-clusters-create"
    data1 = {}
    data1.merge!("region": crdbregion)
    data1.merge!("azs": allazs)
    data1.merge!("vmtype": k8svmtype)
    data1.merge!("cidrip": vpccidrip)
    data1.merge!("csvzones": allazcsv)
    data1.merge!("nodecount": nodecount)
    cm1 = build_commands(cmds1, data1)
    ph1.merge!("create-clstr#{i}": cm1)

    cmds2 ="get-pods-context"
    data2 = {}
    data2.merge!("context": contextid)
    cm2 = build_commands(cmds2, data2)
    ph2.merge!("get-pods-clstr#{i}": cm2)

    cmds3 = "create-clusterrolebinding"
    data3 = {}
    data3.merge!("user": userid)
    data3.merge!("account": account)
    data3.merge!("context": contextid)
    cm3 = build_commands(cmds3, data3)
    ph3.merge!("create-rolebind-clstr#{i}": cm3)

    cmds4 = "get-pods-context"
    data4 = {}
    data4.merge!("context": contextid)
    cm4 = build_commands(cmds4, data4)
    ph4.merge!("get-pods-clstr#{i}": cm4)

    cmds5 = "create-f-client-secure"
    data5 = {}
    data5.merge!("context": contextid)
    cm5 = build_commands(cmds5, data5)
    ph5.merge!("create-clientsec-clstr#{i}": cm5)

    cmds6 = "exec-client-context-sql"
    data6 = {}
    data6.merge!("context": contextid)
    data6.merge!("namespace": k8snamespace)
    cm6 = build_commands(cmds6, data6)
    ph6.merge!("exec-clientsql-clstr#{i}": cm6)

    for x in allazs do
        # Build the contexts/regions JSON objects
        json_cntx.merge!("#{x}": contextid)
        json_regs.merge!("#{x}": crdbregion)
    end

    cmds7 = "port-fwd-crdb"
    data7 = {}
    data7.merge!("context": contextid)
    data7.merge!("clusternum": i )
    data7.merge!("uiport": crdbuiport)
    data7.merge!("namespace": k8snamespace)
    cm7 = build_commands(cmds7, data7)
    ph7.merge!("port-fwd-clstr#{i}-#{x}": cm7)

    cmds8 = "scale-cluster"
    data8 = {}
    data8.merge!("context": contextid)
    data8.merge!("scale": nodecount )
    data8.merge!("namespace": k8snamespace)
    cm8 = build_commands(cmds8, data8)
    phup.merge!("scale-clstr#{i}-#{x}": cm8)

    cmds8d = "scale-cluster"
    data8d = {}
    data8d.merge!("context": contextid)
    data8d.merge!("scale": "0" )
    data8d.merge!("namespace": k8snamespace)
    cm8d = build_commands(cmds8d, data8d)
    phdown.merge!("scale-clstr#{i}-#{x}": cm8d)


    cmdssd = "create-ssd-storage"
    datasd = {}
    datasd.merge!("context": contextid)
    cmsd = build_commands(cmdssd, datasd)
    phssd.merge!("ssd-clstr#{i}-#{x}": cmsd)

    cmdelssd = "delete-ssd-storage"
    datasdelssd = {}
    datasdelssd.merge!("context": contextid)
    cmssdel = build_commands(cmdelssd, datasdelssd)
    phdelssd.merge!("ssd-clstr#{i}-#{x}": cmssdel)

    cmdelclstr = "delete-ssd-storage"
    datadelclstr = {}
    datadelclstr.merge!("clusternum": i )
    datadelclstr.merge!("context": contextid)
    cmdelclst = build_commands(cmdelclstr, datadelclstr)
    phdelclstr.merge!("ssd-clstr#{i}-#{x}": cmdelclst)

    cmdsdba = "create-db-admin"
    datadba = {}
    datadba.merge!("context": contextid)
    datadba.merge!("uiuser": crdbuiuser )
    datadba.merge!("uipass": crdbuipass )
    datadba.merge!("namespace": k8snamespace)
    cmdba = build_commands(cmdsdba, datadba)
    phdba.merge!("dba-clstr#{i}-#{x}": cmdba)

    
    cmdslic = "apply-enterprise-license"
    datalic = {}
    datalic.merge!("context": contextid)
    datalic.merge!("license": crdbentlic )
    datalic.merge!("orgid": crdborgid)
    datalic.merge!("namespace": k8snamespace)
    cmlic = build_commands(cmdslic, datalic)
    phlic.merge!("dba-clstr#{i}-#{x}": cmlic)

end

def overwrite_markdown(tmpl, data, pattern)
    text = [] 
    data.map{|key, value| text.append("#{value}\n\n")}
    output = text.join("")
    original = File.read(tmpl)
    changes = original.gsub(pattern, output)
    File.open(tmpl, "w") {|file| file.puts changes }
    #puts "-----------------"
    #puts output
end


## Populate template file, back it up first, the following looks for double curly brackets vars to replace

# Title
pattern = "{{ title }}"
data = { "title": "CRDB Deployment in #{cloud.upcase} Multiregion K8s Cluster"}
overwrite_markdown(tmpl, data, pattern)

current_time = DateTime.now
cdt = current_time.strftime "%m/%d/%Y %H:%M:%S"
pattern = "{{ timestamp }}"
data = {"timestamp": cdt}
overwrite_markdown(tmpl, data, pattern)

# Get local env information
pattern = "{{ local-gcloud-env }}"
data = {}
data.merge!("email": account)
data.merge!("user": userid)
data.merge!("project": project)
data.merge!("zone": zonenow)
data.merge!("region": regionnow)
overwrite_markdown(tmpl, data, pattern)

# Create the Firewall
pattern = "{{ gce-firewall }}"
data = {"gce-firewall": phfw}
overwrite_markdown(tmpl, data, pattern)

# Create the LB for K8s
pattern = "{{ gke-lb }}"
data = {"lb": phlb}
overwrite_markdown(tmpl, data, pattern)

# Create K8s Cluster
pattern = "{{ create-k8s-cluster }}"
data = ph1
overwrite_markdown(tmpl, data, pattern)

# Create the contexts and regions JSON 
pattern = "{{ json-contexts }}"
jsc = "contexts = #{JSON.pretty_generate(json_cntx)}\n"
data = {"json-context": jsc}
overwrite_markdown(tmpl, data, pattern)
# TODO: Overwrite Python file here
pattern = "{{ json-regions }}"
jsr = "regions = #{JSON.pretty_generate(json_regs)}\n"
data = {"json-context": jsr}
overwrite_markdown(tmpl, data, pattern)
# TODO: Overwrite Python file here
# TODO: Run the YAML configurator script here



# Execute the python script
pattern = "{{ change-dir }}"
data = {"dir": phcd}
overwrite_markdown(tmpl, data, pattern)
pattern = "{{ run-setup-script }}"
data = {"setup": phpy}
overwrite_markdown(tmpl, data, pattern)

# Get Cluster Context
pattern = "{{ get-k8s-context }}"
data = {"context": phcntxt}
overwrite_markdown(tmpl, data, pattern)

# Get SSD Storage
pattern = "{{ create-ssd-storage }}"
data = phssd
overwrite_markdown(tmpl, data, pattern)

# Get Cluser Role Binding
pattern = "{{ create-clusterrolebinding }}"
data = ph3
overwrite_markdown(tmpl, data, pattern)

# Get Pods
pattern = "{{ get-pods }}"
data = ph4
overwrite_markdown(tmpl, data, pattern)

# Get Client Secure
pattern = "{{ client-secure }}"
data = ph5
overwrite_markdown(tmpl, data, pattern)

# Get access db console
pattern = "{{ access-db-console }}"
data = ph6
overwrite_markdown(tmpl, data, pattern)

pattern = "{{ port-forward }}"
data = ph7
overwrite_markdown(tmpl, data, pattern)

# Create a DB user admin
pattern = "{{ dba }}"
data = phdba
overwrite_markdown(tmpl, data, pattern)

# Create the firewall
pattern = "{{ gce-firewall }}"
data = {"gce-firewall": phfw}
overwrite_markdown(tmpl, data, pattern)

# Update license
pattern = "{{ enterprise-license }}"
data = phlic
overwrite_markdown(tmpl, data, pattern)

# Scale down
pattern = "{{ scale-down }}"
data = phdown
overwrite_markdown(tmpl, data, pattern)

# Scale down
pattern = "{{ scale-up }}"
data = phup
overwrite_markdown(tmpl, data, pattern)

# Teardown Resources
pattern = "{{ teardown-crdb }}"
data = {"teardown": phdelrs} 
overwrite_markdown(tmpl, data, pattern)

# Delete SSD Storage
pattern = "{{ delete-ssd-storage }}"
data = phdelssd
overwrite_markdown(tmpl, data, pattern)

# Delete K8s Clusters
pattern = "{{ delete-k8s-cluster }}"
data = phdelclstr
overwrite_markdown(tmpl, data, pattern)

## Clean up files and dirs
# FileUtils.rm_rf(tmpdir)
