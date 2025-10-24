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
retry "install nano subscription-manager kbd insights-client  -y"

# subscription-manager unregister

setenforce 0

