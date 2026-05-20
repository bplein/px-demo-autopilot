#!/usr/bin/env bash

clear 
if ! type "pv" > /dev/null; then
  echo ""
  echo "This demo requires pv (pipe viewer), please install via your package manager"
  exit
fi
source ./util.sh

export namespace=autopilot-demo
desc ""
desc "First lets create a namespace to run our application"
run "kubectl create ns $namespace"


desc "Now lets look at AutoPilot's configmap"
run "kubectl -n portworx get configmaps autopilot-config -o yaml | more"
desc ""
desc "This ConfigMap is already running, but let's patch it to run every 2 seconds instead of 10, just for this demo"
run ""
kubectl -n portworx patch configmap autopilot-config --type=merge --patch '{"data":{"config.yaml":"providers:\n   - name: default\n     type: prometheus\n     params: url=http://px-prometheus:9090\nmin_poll_interval: 2"}}'


desc "Let's look at the Autopilot rule we are going to use for our application"
run "cat grow-pvc-rule.yaml"
run "kubectl -n portworx create -f grow-pvc-rule.yaml"


desc "Let's create a storage class for our application."
desc "Storage classes allow Kubernetes to tell the underlying volume driver how to set up the volumes for capabilites such as IO profiles, HA levels, etc."
run "cat px-repl3-sc-demotemp.yaml"
run "kubectl create -f px-repl3-sc-demotemp.yaml"

desc ""
desc "Now create a volume for the application."

run "cat px-postgres-pvc.yaml"
run "kubectl -n $namespace apply -f px-postgres-pvc.yaml"

echo -n postgres123 > password.txt
kubectl -n $namespace create secret generic postgres-pass --from-file=password.txt 2>&1 >/dev/null


desc ""
desc "And now we'll take a look at the application in YAML format and deploy it (hit CTRL-C to stop watching the application when it's up)"
run "cat postgres-app.yaml"
run "kubectl -n $namespace create -f postgres-app.yaml"
watch kubectl -n $namespace get pods -l app=postgres -o wide

#clear the screen
clear

desc ""
desc "Our rule requires that we label the namespace and any volume we want to watch, let's do that"
run "kubectl label namespaces $namespace type=db --overwrite=true"
run "kubectl -n $namespace label pvc px-postgres-pvc app=postgres --overwrite=true"
desc ""

desc ""
desc "We are going to exec into the Postgres pod and run a command to populate data, and then get the count"
run "kubectl -n $namespace get pods -l app=postgres"
POD=$(kubectl -n $namespace get pods -l app=postgres | grep Running | grep 1/1 | awk '{print $1}')
export POD
desc "Our pod is called $POD"
desc ""
desc "Create the database"
run "kubectl -n $namespace exec -i $POD -- psql << EOF
create database pxdemo;
\l
\q
EOF"

desc ""
desc "Populate the database with test data"
run "kubectl -n $namespace exec -i $POD -- pgbench -i -s 100 pxdemo;"

##########
# get count
##########
desc ""
desc "Let's get the count of records from the database table"

POD=$(kubectl -n $namespace get pods -l app=postgres | grep Running | grep 1/1 | awk '{print $1}')
export POD
run "kubectl -n $namespace exec -i $POD -- psql pxdemo<< EOF
select count(*) from pgbench_accounts;
\q
EOF"
##########
desc "Now that there's over 50% capacity utilization, let's watch the PVC grow online"
watch kubectl -n $namespace get pod,pvc


