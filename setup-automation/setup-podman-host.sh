#!/bin/bash
retry() {
    for i in {1..3}; do
        echo "Attempt $i: $2"
        if $1; then
            return 0
        fi
        [ $i -lt 3 ] && sleep 5
    done
    echo "Failed after 3 attempts: $2"
    exit 1
}

retry "curl -k -L https://${SATELLITE_URL}/pub/katello-server-ca.crt -o /etc/pki/ca-trust/source/anchors/${SATELLITE_URL}.ca.crt"
retry "update-ca-trust"
KATELLO_INSTALLED=$(rpm -qa | grep -c katello)
if [ $KATELLO_INSTALLED -eq 0 ]; then
  retry "rpm -Uhv https://${SATELLITE_URL}/pub/katello-ca-consumer-latest.noarch.rpm"
fi
subscription-manager status
if [ $? -ne 0 ]; then
    retry "subscription-manager register --org=${SATELLITE_ORG} --activationkey=${SATELLITE_ACTIVATIONKEY}"
fi
retry "dnf install yum-utils jq podman wget git ansible-core nano -y"


setenforce 0
firewall-cmd --permanent --add-port=2000:2003/tcp
firewall-cmd --permanent --add-port=6030:6033/tcp
firewall-cmd --permanent --add-port=8065:8065/tcp
firewall-cmd --reload

# Grab sample switch config
rm -rf /opt/ceos-setup

ansible-galaxy collection install community.general

mkdir /opt/ceos-setup/

git clone https://github.com/nmartins0611/Instruqt_netops.git /opt/ceos-setup/

### Configure containers

podman pull quay.io/nmartins/ceoslab-rh

## Create Networks

podman network create net1
podman network create net2
podman network create net3
podman network create loop
podman network create management

podman run -d --network management --memory=4g --name=ceos1 --privileged -v /opt/ceos-setup/sw01/sw01:/mnt/flash/startup-config -e INTFTYPE=eth -e ETBA=1 -e SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 -e CEOS=1 -e EOS_PLATFORM=ceoslab -e container=podman -p 6031:6030 -p 2001:22/tcp quay.io/nmartins/ceoslab-rh /sbin/init systemd.setenv=INTFTYPE=eth systemd.setenv=ETBA=1 systemd.setenv=SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 systemd.setenv=CEOS=1 systemd.setenv=EOS_PLATFORM=ceoslab systemd.setenv=container=podman  ##
podman run -d --network management --memory=4g --name=ceos2 --privileged -v /opt/ceos-setup/sw02/sw02:/mnt/flash/startup-config -e INTFTYPE=eth -e ETBA=1 -e SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 -e CEOS=1 -e EOS_PLATFORM=ceoslab -e container=podman -p 6032:6030 -p 2002:22/tcp quay.io/nmartins/ceoslab-rh /sbin/init systemd.setenv=INTFTYPE=eth systemd.setenv=ETBA=1 systemd.setenv=SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 systemd.setenv=CEOS=1 systemd.setenv=EOS_PLATFORM=ceoslab systemd.setenv=container=podman  ##systemd.setenv=MGMT_INTF=eth0
podman run -d --network management --memory=4g --name=ceos3 --privileged -v /opt/ceos-setup/sw03/sw03:/mnt/flash/startup-config -e INTFTYPE=eth -e ETBA=1 -e SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 -e CEOS=1 -e EOS_PLATFORM=ceoslab -e container=podman -p 6033:6030 -p 2003:22/tcp quay.io/nmartins/ceoslab-rh /sbin/init systemd.setenv=INTFTYPE=eth systemd.setenv=ETBA=1 systemd.setenv=SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 systemd.setenv=CEOS=1 systemd.setenv=EOS_PLATFORM=ceoslab systemd.setenv=container=podman  ##systemd.setenv=MGMT_INTF=eth0


# ## Attach Networks
podman network connect loop ceos1
podman network connect net1 ceos1
podman network connect net3 ceos1

podman network connect loop ceos2
podman network connect net1 ceos2
podman network connect net2 ceos2

podman network connect loop ceos3
podman network connect net2 ceos3
podman network connect net3 ceos3

## Wait for Switches to load conf
sleep 60

# ## Create a script to refresh ceos management IPs in /etc/hosts on every boot
cat <<'HOSTS_SCRIPT' > /usr/local/bin/update-ceos-hosts.sh
#!/bin/bash
# Remove any existing ceos entries to avoid duplicates
sed -i '/[[:space:]]ceos[123]$/d' /etc/hosts

# Wait for each container to be running before inspecting
for name in ceos1 ceos2 ceos3; do
    timeout 120 bash -c "until podman inspect ${name} --format '{{.State.Running}}' 2>/dev/null | grep -q true; do sleep 2; done"
done

# Write fresh management IPs
for name in ceos1 ceos2 ceos3; do
    ip=$(podman inspect ${name} | jq -r '.[] | .NetworkSettings.Networks.management | .IPAddress')
    echo "${ip} ${name}" >> /etc/hosts
done
HOSTS_SCRIPT
chmod +x /usr/local/bin/update-ceos-hosts.sh

## Create systemd service to run the script at boot after podman starts
cat <<'UNIT' > /etc/systemd/system/update-ceos-hosts.service
[Unit]
Description=Refresh ceos container IPs in /etc/hosts
After=network-online.target ceos-containers.service
Wants=network-online.target
Requires=ceos-containers.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-ceos-hosts.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable update-ceos-hosts.service

## Create a startup script that recreates ceos containers with proper port forwarding
cat <<'CEOS_SCRIPT' > /usr/local/bin/start-ceos-containers.sh
#!/bin/bash
IMAGE="quay.io/nmartins/ceoslab-rh"
COMMON_ENV="-e INTFTYPE=eth -e ETBA=1 -e SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 -e CEOS=1 -e EOS_PLATFORM=ceoslab -e container=podman"
COMMON_SYSENV="systemd.setenv=INTFTYPE=eth systemd.setenv=ETBA=1 systemd.setenv=SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 systemd.setenv=CEOS=1 systemd.setenv=EOS_PLATFORM=ceoslab systemd.setenv=container=podman"

# Remove old containers (port proxy is stale after reboot)
for name in ceos1 ceos2 ceos3; do
    podman stop $name 2>/dev/null
    podman rm $name 2>/dev/null
done

# Recreate containers with fresh port forwarding
podman run -d --network management --memory=4g --name=ceos1 --privileged -v /opt/ceos-setup/sw01/sw01:/mnt/flash/startup-config $COMMON_ENV -p 6031:6030 -p 2001:22/tcp $IMAGE /sbin/init $COMMON_SYSENV
podman run -d --network management --memory=4g --name=ceos2 --privileged -v /opt/ceos-setup/sw02/sw02:/mnt/flash/startup-config $COMMON_ENV -p 6032:6030 -p 2002:22/tcp $IMAGE /sbin/init $COMMON_SYSENV
podman run -d --network management --memory=4g --name=ceos3 --privileged -v /opt/ceos-setup/sw03/sw03:/mnt/flash/startup-config $COMMON_ENV -p 6033:6030 -p 2003:22/tcp $IMAGE /sbin/init $COMMON_SYSENV

# Reattach additional networks
podman network connect loop ceos1
podman network connect net1 ceos1
podman network connect net3 ceos1

podman network connect loop ceos2
podman network connect net1 ceos2
podman network connect net2 ceos2

podman network connect loop ceos3
podman network connect net2 ceos3
podman network connect net3 ceos3

# Wait for SSH to be available on each container's mapped port
declare -A ports=([ceos1]=2001 [ceos2]=2002 [ceos3]=2003)
for name in ceos1 ceos2 ceos3; do
    port=${ports[$name]}
    echo "Waiting for SSH on $name (port $port)..."
    timeout 300 bash -c "until bash -c 'echo > /dev/tcp/localhost/$port' 2>/dev/null; do sleep 5; done"
    echo "$name is ready"
done
CEOS_SCRIPT
chmod +x /usr/local/bin/start-ceos-containers.sh

## Create a dedicated systemd service to restart the ceos containers on boot
cat <<'EOF' > /etc/systemd/system/ceos-containers.service
[Unit]
Description=Start ceos switch containers
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/start-ceos-containers.sh
ExecStop=/usr/bin/podman stop ceos1 ceos2 ceos3
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ceos-containers

## Get management IP (initial population for this first run)
/usr/local/bin/update-ceos-hosts.sh



## Install Gmnic
bash -c "$(curl -sL https://get-gnmic.kmrd.dev)"

#################################################################

cat <<EOF | tee /etc/yum.repos.d/influxdb.repo
[influxdb]
name = InfluxDB Repository - RHEL \$releasever
baseurl = https://repos.influxdata.com/rhel/\$releasever/\$basearch/stable
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdata-archive.key

EOF

dnf install telegraf -y

cat <<EOF | tee /etc/telegraf/telegraf.conf


############################################## SWITCH 01  #############################################

[[inputs.gnmi]]
## Address and port of the GNMI GRPC server
 addresses = ["localhost:6031"] ## Container Switch
 name_override = "ceos1"
## credentials
 username = "ansible"
 password = "ansible"

## redial in case of failures after
# redial = "10s"

[[inputs.gnmi.subscription]]
  name = "Ethernet1"
  origin = "openconfig"
  subscription_mode = "on_change"
  path = "/interfaces/interface[name=Ethernet1]/state/admin-status"
  sample_interval = "2s"

[[inputs.gnmi.subscription]]
## Name of the measurement that will be emitted
  name = "bgp_neighbor_state_ceos1"
  origin = "openconfig"
  path = "/network-instances/network-instance/protocols/protocol/bgp/neighbors/neighbor/state/session-state"
  subscription_mode = "on_change"
  sample_interval = "2s"

############################################## SWITCH 02  #############################################


[[inputs.gnmi]]
## Address and port of the GNMI GRPC server
 addresses = ["localhost:6032"]
 name_override = "ceos2"
## credentials
 username = "ansible"
 password = "ansible"

## redial in case of failures after
# redial = "10s"

[[inputs.gnmi.subscription]]
  name = "Ethernet1"
  origin = "openconfig"
  subscription_mode = "on_change"
  path = "/interfaces/interface[name=Ethernet1]/state/admin-status"
  sample_interval = "2s"


############################################## SWITCH 03  #############################################


[[inputs.gnmi]]
## Address and port of the GNMI GRPC server
 addresses = ["localhost:6033"]
 name_override = "ceos3"
## credentials
 username = "ansible"
 password = "ansible"

## redial in case of failures after
# redial = "10s"

[[inputs.gnmi.subscription]]
  name = "Ethernet1"
  origin = "openconfig"
  subscription_mode = "on_change"
  path = "/interfaces/interface[name=Ethernet1]/state/admin-status"
  sample_interval = "1s"

############################################## OUTPUTS  ####################################################

[outputs.kafka]
# URLs of kafka brokers
  brokers = ["broker:9092"] # EDIT THIS LINE
# Kafka topic for producer messages
  topic = "network"
  data_format = "json"

EOF

systemctl enable --now telegraf

sudo rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch

cat <<EOF | tee /etc/yum.repos.d/elastic.repo
[elastic-8.x]
name=Elastic repository for 8.x packages
baseurl=https://artifacts.elastic.co/packages/8.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md

EOF

#sudo yum install filebeat -y
sudo yum install filebeat-8.18.8 -y

cat <<EOF | tee  /etc/filebeat/filebeat.yml

filebeat.inputs:
- type: journald
  id: everything

output.kafka:
   # List of Kafka brokers
  hosts: ["broker:9092"]
  topic: 'network'
  partition.round_robin:
  reachable_only: false
  required_acks: 1
  compression: gzip

EOF

sleep 30

systemctl enable --now filebeat

yum install httpd -y
yum install rsync -y

git clone https://github.com/nmartins0611/aap25-roadshow-content.git /tmp/lab-setup
sudo rsync -av /tmp/lab-setup/lab-resources/* /var/www/html/

systemctl enable --now httpd

mkdir /var/www/html/chaos
chmod 777 /var/www/html/chaos
