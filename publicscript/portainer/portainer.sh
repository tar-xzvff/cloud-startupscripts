#!/bin/bash

apt-get update -y

apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

apt-get install docker-ce docker-ce-cli containerd.io -y

curl -L "https://github.com/docker/compose/releases/download/1.25.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

chmod +x /usr/local/bin/docker-compose

GLOBAL_IP=`curl inet-ip.info`
cat << EOF > /etc/docker/daemon.json
{
   "ip":"${GLOBAL_IP}"
}
EOF

systemctl restart docker

mkdir /opt/portainer
cd /opt/portainer
wget https://downloads.portainer.io/docker-compose.yml
docker-compose up -d
