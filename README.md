# Kubernetes on Raspberry Pi

## Table of content
1. [Prerequisites](#prerequisites)
  * [Hardware](#hardware)
  * [Raspberry Pi Configuration](#raspberry-pi-configuration)
2. [Cluster Setup](#cluster-setup)
  * [Kubernetes Prerequisites](#kubernetes-prerequisites)
  * [Initialize Kubernetes master](#initialize-kubernetes-master)
  * [Install worker nodes](#install-worker-nodes)
3. [Cluster Sotware Deployment](#tutorial)
  * [Create a Deployment](#create-a-deployment)
  * [Create a Service](#create-a-service)
  * [Create an Ingress](#create-an-ingress)

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
1. Flash your sd card with the latest version `raspbian stretch`.
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
