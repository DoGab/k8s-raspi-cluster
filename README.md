# Kubernetes on Raspberry Pi

## Table of content
1. [Prerequisites](#prerequisites)
  * [Hardware](#hardware)
  * [Raspberry Pi Configuration](#raspberry-pi-configuration)
2. [Cluster Setup](#cluster-setup)
  * [Kubernetes Prerequisites](#kubernetes-prerequisites)
  * [Initialize Kubernetes master](#initialize-kubernetes-master)
  * [Install worker nodes](#install-worker-nodes)
3. [Cluster Sotware Deployment](#cluster-software-deployment)
  * [Choose your software](#choose-your-software)
  * [Create a namespace](#create-a-namespace)
  * [Create a Deployment](#create-a-deployment)
  * [Create a Service](#create-a-service)
  * [Create an Ingress](#create-an-ingress)
  * [Persistent storage](#persistent-storage)
  * [Additional container parameters](#additional-container-parameters)

This repository contains a guide to install kubernetes (version `1.15.0`) on a Raspberry Pi cluster. It further provides some yaml files for the deployment of some software I use at home on my Cluster. I'll try to periodically add new stuff and keeping the repository up to date.

## Prerequisites
### Hardware

I used 3 Raspberry Pis for the setup of my Kubernetes Cluster.

* 3 Raspberry pis
* 3 SD-Cards with at least 16GB. I recommend 32gb sd cards.
* Raspberry Pi Stack Case from aliexpress.com. You can find it [here](https://www.aliexpress.com/item/32916001567.html?spm=a2g0s.9042311.0.0.4c164c4d2g6PJB)

![Raspberry Pi Stack](/images/raspberry-pi-stack.jpeg "Raspberry Pi Cluster")

### Raspberry Pi Configuration
* Raspbian - Flash Raspbian on all your SD-Cards and boot your pis. For using Kubernetes Version `1.14` and newer you should use raspbian `4.19.46-v7+ or newer`. Before that version the `PID Cgroup` is unavailable. Further reading [here](https://github.com/teamserverless/k8s-on-raspbian/issues/16)
  * Configure the raspberry pis according to your needs.
* Static IP address (use `/etc/dhcpd.conf`)

#### Workaround
Since docker isn't available for raspbian buster yet you can't use that release. Either you wait until docker is avaialable or you follow this workaround.
1. Flash your sd card with the latest version `raspbian stretch`. Get it [here](http://downloads.raspberrypi.org/raspbian/images/)
2. Update the kernel with the latest unstable version. Run `sudo rpi-update` and reboot the raspberry pi afterwards.
3. Check that the kernel version is newer than `4.19.46-v7+`.
```bash
pi@k8minion1:~ $ uname -a
Linux k8minion1 4.19.56-v7+ #1242 SMP Wed Jun 26 17:31:47 BST 2019 armv7l GNU/Linux
```
4. Check if the `pids` cgroup is available with `cat /proc/cgroups`.
```bash
pi@k8minion1:~ $ cat /proc/cgroups
#subsys_name	hierarchy	num_cgroups	enabled
cpuset	7	20	1
cpu	6	94	1
cpuacct	6	94	1
blkio	5	94	1
memory	4	129	1
devices	3	94	1
freezer	9	20	1
net_cls	8	20	1
pids	2	99	1
```
5. Follow the instructions in the cluster setup part.

## Cluster Setup
### Kubernetes Prerequisites
Login to all of your raspberry pis and create/copy the script below to the pi users home directory and name it `install-k8-prereq.sh`.
```bash
#!/bin/sh

# Install Docker
curl -sSL get.docker.com | sh && \
sudo usermod pi -aG docker

# Disable Swap
sudo dphys-swapfile swapoff && \
sudo dphys-swapfile uninstall && \
sudo update-rc.d dphys-swapfile remove
sudo systemctl disable dphys-swapfile

echo Adding " cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1" to /boot/cmdline.txt
sudo cp /boot/cmdline.txt /boot/cmdline_backup.txt
orig="$(head -n1 /boot/cmdline.txt) cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1"
echo $orig | sudo tee /boot/cmdline.txt

# https://github.com/kubernetes/kubernetes/issues/71305#issuecomment-479558920
# Change iptables to legacy mode
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy

# Add repo list and install kubeadm
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - && \
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list && \
sudo apt-get update -q && \
sudo apt-get install -qy kubeadm
```

Execute the script to install all prerequisites to install and run Kubernetes.
```bash
pi@k8master:~ $ sh install-k8-prereq.sh
```
After the script has finished, reboot the raspberry pi.

### Initialize Kubernetes master
Run
```bash
$ sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```
It will take several minutes until you get an output. Once the command has finished your output should look similar to this:

```bash
pi@k8master:~ $ sudo kubeadm init --pod-network-cidr=10.244.0.0/16
[init] Using Kubernetes version: v1.15.0
...
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 192.168.2.120:6443 --token hodslk.9monok7xjf1sksiu \
    --discovery-token-ca-cert-hash <yourhash>
```

Run the 3 commands told in the output of the previous command.

```bash
pi@k8master:~ $ mkdir -p $HOME/.kube
pi@k8master:~ $ sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
pi@k8master:~ $ sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Check that your master is running. It will get the status `ready` after some minutes.
```bash
pi@k8master:~ $ kubectl get nodes
NAME       STATUS     ROLES    AGE    VERSION
k8master   NotReady   master   2m1s   v1.15.0
```

### Install worker nodes
Join the worker nodes into the cluster. To do so run the following command on every node you want to join.
```bash
pi@k8minion1:~ $ kubeadm join 192.168.2.120:6443 --token 6xclsv.l83i9exyrujkyb82 \
    --discovery-token-ca-cert-hash <yourhash>
```

This will generate an output like the following:
```bash
...
This node has joined the cluster:
* Certificate signing request was sent to apiserver and a response was received.
* The Kubelet was informed of the new secure connection details.

Run 'kubectl get nodes' on the control-plane to see this node join the cluster.
```

### Install a Network plugin
Install a network plugin on the master raspberry pi. Choose one from the list here: https://kubernetes.io/docs/concepts/cluster-administration/addons/. I'm going to use `flannel` as the network plugin.
```bash
pi@k8master:~ $ kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/62e44c867a2846fefb68bd5f178daf4da3095ccb/Documentation/kube-flannel.yml
```

After you have run that command on them master you should see all nodes getting ready by running `kubectl get nodes`.
```bash
pi@k8master:~ $ kubectl get nodes
NAME        STATUS   ROLES    AGE     VERSION
k8master    Ready    master   73m     v1.15.0
k8minion1   Ready    <none>   41m     v1.15.0
k8minion2   Ready    <none>   7m12s   v1.15.0
```

Also all pods should be running.
```bash
pi@k8master:~ $ kubectl get pods --all-namespaces
NAMESPACE     NAME                               READY   STATUS    RESTARTS   AGE
kube-system   coredns-5c98db65d4-4dwk2           1/1     Running   0          61m
kube-system   coredns-5c98db65d4-h9c2j           1/1     Running   0          61m
kube-system   etcd-k8master                      1/1     Running   0          73m
kube-system   kube-apiserver-k8master            1/1     Running   2          72m
kube-system   kube-controller-manager-k8master   1/1     Running   0          73m
kube-system   kube-flannel-ds-arm-5mqtg          1/1     Running   0          5m51s
kube-system   kube-flannel-ds-arm-6x6v4          1/1     Running   0          5m51s
kube-system   kube-flannel-ds-arm-n42kf          1/1     Running   0          5m51s
kube-system   kube-proxy-gspck                   1/1     Running   1          42m
kube-system   kube-proxy-j8mxf                   1/1     Running   0          8m22s
kube-system   kube-proxy-nln46                   1/1     Running   0          61m
kube-system   kube-scheduler-k8master            1/1     Running   0          74m
```

**Yaayy!** The Kubernetes Cluster is now ready to deploy some software!

## Cluster Software Deployment

All files needed for this Tutorial are provided in this repository. The best way is to clone it in the pi-users home directory and change into it.
```bash
pi@k8master:~ $ git clone https://github.com/DoGab/k8s-raspi-cluster.git
pi@k8master:~ $ cd k8-raspi-cluster
```

### Choose your Software
For my home network i wanted to setup a simple wiki solution which reads markdown files from a directory and displays them on a webservice. For this purpose i found gollum.com.

I found several docker containers linked on the offical gollum-repository from other users. The problem was that none of them was made to run on a raspberry pi, so i had to build the container on my own. You can find the container [here](https://hub.docker.com/r/dogab/docker-gollum).

#### Compatibility check
1. Get the CPU-Model of the raspberry pi.
```bash
pi@k8minion1:~ $ cat /proc/cpuinfo | grep model
model name	: ARMv7 Processor rev 5 (v7l)
model name	: ARMv7 Processor rev 5 (v7l)
model name	: ARMv7 Processor rev 5 (v7l)
model name	: ARMv7 Processor rev 5 (v7l)
```

2. Get the release of your raspberry pi.
```bash
pi@k8minion1:~ $ cat /etc/os-release
PRETTY_NAME="Raspbian GNU/Linux 9 (stretch)"
NAME="Raspbian GNU/Linux"
VERSION_ID="9"
VERSION="9 (stretch)"
ID=raspbian
ID_LIKE=debian
HOME_URL="http://www.raspbian.org/"
SUPPORT_URL="http://www.raspbian.org/RaspbianForums"
BUG_REPORT_URL="http://www.raspbian.org/RaspbianBugs"
```

3. For the raspberry pi 2 and 3 the cpu model is `arm32v7`.

4. Check now if the software you want to deploy is available for `arm32v7` by investigating the `TAGS` section on Dockerhub or having a look at the first keyword `FROM *` in the `Dockerfile`.
  ```bash
  DockerFROM arm32v7/ruby:2.7-rc-buster

  MAINTAINER Dominic Gabriel <domi94@gmx.ch>
  ...
  ```

### Create a namespace
First of all we need to create a Namespace for our Application. Namespaces are resources to group together parts of applications and separate them from others. Build the namespace by pasting the following few lines into a yaml file/or get it from the repository [gollum-namespace](gollum/gollum-namespace.yaml).

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: wiki
```

Create the namespace called `wiki`.
```bash
pi@k8master:~/k8s-raspi-cluster $ kubectl apply -f gollum/gollum-namespace.yaml
```

### Create a Deployment

Now that the namespace for `gollum` is prepared we are going to create a simple deployment with no additional parameters.

Run
```bash
pi@k8master:~ $ kubectl create deployment gollum --image=dogab/docker-gollum:v1 --dry-run=true -o yaml -n wiki
```

Save the output to a yaml file called `gollum-deployment.yaml` and apply it on the cluster or use the file `gollum/gollum-arm32v7-deployment.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  creationTimestamp: null
  labels:
    app: gollum
  name: gollum
  namespace: wiki
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gollum
  strategy: {}
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: gollum
    spec:
      containers:
      - image: dogab/docker-gollum:v1
        name: docker-gollum
        resources: {}
status: {}
```

```bash
pi@k8master:~/k8s-raspi-cluster $ kubectl apply -f gollum/gollum-arm32v7-deployment.yaml
```
If the deployment was successfull you'll see it by getting deployments and pods in the wiki namespace.

```bash
pi@k8master:~ $ kubectl get deployment -n wiki
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
gollum   1/1     1            1           33h

pi@k8master:~ $ kubectl get pods -n wiki
NAME                      READY   STATUS    RESTARTS   AGE
gollum-66f856c46b-bqf66   1/1     Running   0          33h
```

### Create a Service
As a next step we need to create a service for our application to make it available for the cluster itself.
```bash
pi@k8master:~ $ kubectl expose deployment gollum --target-port=4567 --port=8000 --dry-run=true -o yaml -n wiki
```

Save the output into a yaml file called `gollum-service.yaml` or use the file `gollum/gollum-service.yaml` from this repository.



Add the line `namespace: wiki` after the line `name: gollum` so that your file looks like this...
```yaml
apiVersion: v1
kind: Service
metadata:
  creationTimestamp: null
  labels:
    app: gollum
  name: gollum
  namespace: wiki
spec:
  ports:
  - port: 8000
    protocol: TCP
    targetPort: 4567
  selector:
    app: gollum
status:
  loadBalancer: {}
```

... and apply it on the cluster.
```bash
pi@k8master:~/k8s-raspi-cluster $ kubectl apply gollum/gollum-service.yaml
```

Check if the service was created successfully.
```bash
pi@k8master:~ $ kubectl get service -n wiki
NAME     TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)    AGE
gollum   ClusterIP   10.97.54.22   <none>        8000/TCP   33h
```

Also check if the service is available on the cluster by first getting the endpoints.
```bash
pi@k8master:~ $ kubectl get endpoints -n wiki
NAME     ENDPOINTS         AGE
gollum   10.244.1.4:4567   33h
```

After that test the service with curl.
```bash
pi@k8master:~ $ curl http://10.244.1.4:4567/Home
<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="Content-type" content="text/html;charset=utf-8">
  <meta name="MobileOptimized" content="width">
  <meta name="HandheldFriendly" content="true">
  <meta name="viewport" content="width=device-width">
  <link rel="stylesheet" type="text/css" href="/css/gollum.css" media="all">
  <link rel="stylesheet" type="text/css" href="/css/editor.css" media="all">
  <link rel="stylesheet" type="text/css" href="/css/dialog.css" media="all">
  <link rel="stylesheet" type="text/css" href="/css/template.css" media="all">
  <link rel="stylesheet" type="text/css" href="/css/print.css" media="print">

...

</html>
```

### Create an Ingress
To make services available outside of the cluster we need to create Ingress Objects. It functions like a reverse proxy.

First we will deploy the Ingress controller `traefik` to our cluster. You can find some information about traefik [here](https://docs.traefik.io/user-guide/kubernetes/).

To gain `traefik` access to the cluster we first need to create some rbac rules.
```bash
k8s-1:~$ kubectl apply -f https://raw.githubusercontent.com/containous/traefik/v1.7/examples/k8s/traefik-rbac.yaml
clusterrole.rbac.authorization.k8s.io/traefik-ingress-controller created
clusterrolebinding.rbac.authorization.k8s.io/traefik-ingress-controller created
```

After that we can deploy the traefik service account, deployment and service.
```bash
k8s-1:~$ kubectl apply -f https://raw.githubusercontent.com/containous/traefik/v1.7/examples/k8s/traefik-deployment.yaml
serviceaccount/traefik-ingress-controller created
deployment.extensions/traefik-ingress-controller created
service/traefik-ingress-service created
```

Check if the pod and service are working. Check the webservice with curl or the browser on the ports listed on the service overview.
```bash
pi@k8master:~/k8s-raspi-cluster $ kubectl get service -n kube-system
NAME                      TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                       AGE
kube-dns                  ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP        150m
traefik-ingress-service   NodePort    10.98.3.50   <none>        80:31574/TCP,8080:30373/TCP   12s
```

Check the traefik webservice with curl or the browser on the ports listed on the service overview.
```bash
pi@k8master:~/k8s-raspi-cluster $ curl 10.98.3.50:8080/dashboard/
<!doctype html><html class="has-navbar-fixed-top"><head><meta charset="utf-8"><title>Traefik</title><base href="./"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="icon" type="image/x-icon" href="./assets/images/traefik.icon.png"><link href="styles.e21e21d47be645f690e6.bundle.css" rel="stylesheet"/></head><body><app-root></app-root><script type="text/javascript" src="inline.318b50c57b4eba3d437b.bundle.js"></script><script type="text/javascript" src="polyfills.1457c99db4b6dba06e8d.bundle.js"></script><script type="text/javascript" src="scripts.ef668c5c0d42ec4c5e83.bundle.js"></script><script type="text/javascript" src="main.f341693bf9ed22060b42.bundle.js"></script></body></html>
```

Or via browser `http://k8master.gabnetwork.ch:30373/dashboard/`. You can also use any of your nodes to check the service.

Now we are ready to create an ingress object for the already deployed nginx service.

#### Create an ingress object
Create an ingress object to make the service public available. This allows you to configure multiple services being available on the same port.
```yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: gollum
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
  namespace: wiki
spec:
  rules:
  - host: wiki.gabnetwork.ch
    http:
      paths:
      - backend:
          serviceName: gollum
          servicePort: 8000
```
Adjust the `host: wiki.gabnetwork.ch` line to match your desired host.

Apply the ingress object to the cluster.
```bash
pi@k8master:~/k8s-raspi-cluster $ kubectl apply -f gollum/gollum-ingress.yaml
ingress.extensions/gollum created
```

You should now see the Ingress Object deployed in the Web-UI of traefik and a created Ingress object.
```bash
pi@k8master:~ $ kubectl get ingress -n wiki
NAME     HOSTS                ADDRESS   PORTS   AGE
gollum   wiki.gabnetwork.ch             80      33h
```

To access the ingress from your browser you need to have a dns entry or create an entry in `/etc/hosts` on your host. I have a pihole configured in my home network which also manages my dns entries.
```bash
$ vim /etc/hosts
192.168.2.120	k8master.gabnetwork.ch	k8master wiki.gabnetwork.ch
192.168.2.121	k8minion1.gabnetwork.ch	k8minion1 wiki.gabnetwork.ch
192.168.2.122	k8minion2.gabnetwork.ch	k8minion2 wiki.gabnetwork.ch
```

It now is possible to access the nginx service via browser on `http://wiki.gabnetwork.ch:<port of ingresscontroller>`/Home.
```bash
http://wiki.gabnetwork.ch:31574/Home
```

**Yaayy!** We have successfully deployed our first application! If you want to know how we can improve and adapt it, go on with the next chapter.

### Persistent storage
Until now the Application data is saved directly in the pod and only available if the pod is available. As soon as the pod dies all data is lost. Persistent storage enables the application to save data outside of the pod on a central storage device.

Find more information about persistent storage [here](https://kubernetes.io/docs/concepts/storage/persistent-volumes/).

Create an nfs share somewhere on a server.

#### Create a persistent volume
Create the file `wikistorage-pv.yaml` and paste the lines below. Edit the parameter `storage` to adjust the size of your storage volume. Also adjust the parameters `path` and `server` under the `nfs` section to match your nfs server.
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: wikistorage
  namespace: wiki
spec:
  capacity:
    storage: 2Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Recycle
  storageClassName: slow
  nfs:
    path: /volume1/kubestorage/gollum-wiki
    server: 192.168.2.100
```
Apply the file on the cluster so the persistent volume gets created.
```bash
pi@k8master:~/k8s-raspi-cluster $ kubectl apply -f gollum/wikistorage-pv.yaml
persistentvolume/wikistorage created
```
Check if the persistent volume was created successfully.
```bash
pi@k8master:~/k8s-raspi-cluster $ kubectl get pv
NAME          CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   REASON   AGE
wikistorage   2Gi        RWX            Recycle          Available           slow                    7s
```
#### Claim the persistent volume
As we have the persistent volume now we need to claim some storage from it. Paste the lines below in a file called `wikistorage-pvc.yaml` and edit the parameter `storage` to adjust the required size you want to claim from the recently created `PV`.
```yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: wikistorage-claim
  namespace: wiki
spec:
  storageClassName: slow
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
```
Apply the file on the cluster and let it claim some storage.
```bash
pi@k8master:~/k8s-raspi-cluster $ kubectl apply -f gollum/wikistorage-pvc.yaml
persistentvolumeclaim/wikistorage-claim created
```

Check if the claim was successful.
```bash
pi@k8master:~/k8s-raspi-cluster $ kubectl get pvc -n wiki
NAME                STATUS   VOLUME        CAPACITY   ACCESS MODES   STORAGECLASS   AGE
wikistorage-claim   Bound    wikistorage   2Gi        RWX            slow           10s
```

#### Update the deployment
After we have configured the persistent storage we need to make sure it gets mounted/mapped inside a pod. For this reason we need to adjust the deployment. Add the following lines to your deployment file and edit the parameters `claimName` according to your needs. The parameter `mountPath` defines where the storage should be mounted inside of the pod - `/root/wikidata` is the directory where the gollum docker container contains its files.
```yaml
        volumeMounts:
        - mountPath: "/root/wikidata"
          name: mypd
      volumes:
      - name: mypd
        persistentVolumeClaim:
          claimName: wikistorage-claim
```

Adjust your deployment file that it looks like the one below.
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  creationTimestamp: null
  labels:
    app: gollum
  name: gollum
  namespace: wiki
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gollum
  strategy: {}
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: gollum
    spec:
      containers:
      - image: dogab/docker-gollum:v1
        name: docker-gollum
        resources: {}
        volumeMounts:
        - mountPath: "/root/wikidata"
          name: mypd
      volumes:
      - name: mypd
        persistentVolumeClaim:
          claimName: wikistorage-claim
status: {}
```
Apply it on the cluster.
```bash
pi@k8master:~/k8s-raspi-cluster $ kubectl apply -f gollum/gollum-arm32v7-deployment-withpv.yaml
deployment.apps/gollum configured
```
This will update the old gollum deployment, deploy a new pod and delete the old pod as soon as the new pod is in the `running` status.
```bash
pi@k8master:~/k8s-raspi-cluster $ kubectl get pods -n wiki
NAME                      READY   STATUS              RESTARTS   AGE
gollum-66f856c46b-bqf66   1/1     Running             0          2d9h
gollum-6cc5d879f-vzp2z    0/1     ContainerCreating   0          14s
```
As soon as it has finished you'll see one pod again.
```bash
pi@k8master:~/k8s-raspi-cluster $ kubectl get pods -n wiki
NAME                     READY   STATUS    RESTARTS   AGE
gollum-6cc5d879f-vzp2z   1/1     Running   0          10m
```

### Additional container parameters
It's also possible to pass extra parameters to a container inside a pod. Edit the deployment and add the extra parameters below. Those will allow you to upload files to the wiki and getting live previews when writing markdown.
```yaml
args: ["--allow-uploads=page", "--live-preview"]
```

The final deployment file for our gollum wiki looks like this:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  creationTimestamp: null
  labels:
    app: gollum
  name: gollum
  namespace: wiki
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gollum
  strategy: {}
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: gollum
    spec:
      containers:
      - image: dogab/docker-gollum:v1
        name: docker-gollum
        resources: {}
        args: ["--allow-uploads=page", "--live-preview"]
        volumeMounts:
        - mountPath: "/root/wikidata"
          name: mypd
      volumes:
      - name: mypd
        persistentVolumeClaim:
          claimName: wikistorage-claim
status: {}
```

Apply it on the cluster.
```bash
pi@k8master:~/k8s-raspi-cluster $ kubectl apply -f gollum/gollum-arm32v7-deployment-withpv-withparams.yaml
deployment.apps/gollum configured
```

After some minutes a new pod should have been created and the parameters will take effect.
```bash
pi@k8master:~/k8s-raspi-cluster $ kubectl get pods -n wiki
NAME                      READY   STATUS    RESTARTS   AGE
gollum-7dfdf9fb8f-sg9fk   1/1     Running   0          56s
```

**Yaayy** we have deployed an Application and made it's files/content persistent.
