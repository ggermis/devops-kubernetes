#!/bin/bash

CERT_DIR=certificates

# Flannel: 10.200.0.0/16
# Service: 172.50.0.0/24
# K8_service: 172.50.0.1
# DNS service: 172.50.0.10
# Etcd endpoints: 172.17.8.101:2380,172.17.8.102:2380,172.17.8.103:2380
# Master host: 172.17.8.11
# Worker Nodes: 172.17.8.21,172.17.8.22,172.17.8.23

: ${WORKERS:=1,2,3}


MASTER_HOST=172.17.8.11
ETCD_ENDPOINTS=172.17.8.101:2380,172.17.8.102:2380,172.17.8.103:2380

SERVICE_IP_RANGE=172.50.0.0/24
K8_SERVICE=172.50.0.1
DNS_SERVICE_IP=172.50.0.10

POD_NETWORK=10.200.0.0/16



mkdir -p "$CERT_DIR" &&
pushd "$CERT_DIR" && {
	# Root CA
	openssl genrsa -out ca-key.pem 2048
	openssl req -x509 -new -nodes -key ca-key.pem -days 10000 -out ca.pem -subj "/CN=kube-ca"

	# API Server certificates
	cat > openssl.cnf <<-EOT
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
IP.1 = $K8_SERVICE
IP.2 = $MASTER_HOST
EOT
	openssl genrsa -out apiserver-key.pem 2048
	openssl req -new -key apiserver-key.pem -out apiserver.csr -subj "/CN=kube-apiserver" -config openssl.cnf
	openssl x509 -req -in apiserver.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out apiserver.pem -days 365 -extensions v3_req -extfile openssl.cnf


	# Worker Node certificates
	cat > openssl-worker.cnf <<-EOT
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
IP.1 = \$ENV::WORKER_IP
EOT
	for WORKER in ${WORKERS//,/ }; do
		export WORKER_FQDN="worker-0$WORKER"
		export WORKER_IP=172.17.8.$(($WORKER+20))
		openssl genrsa -out ${WORKER_FQDN}-worker-key.pem 2048
		openssl req -new -key ${WORKER_FQDN}-worker-key.pem -out ${WORKER_FQDN}-worker.csr -subj "/CN=${WORKER_FQDN}" -config openssl-worker.cnf
		openssl x509 -req -in ${WORKER_FQDN}-worker.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out ${WORKER_FQDN}-worker.pem -days 365 -extensions v3_req -extfile openssl-worker.cnf
	done
	

	# Admin certificate
	openssl genrsa -out admin-key.pem 2048
	openssl req -new -key admin-key.pem -out admin.csr -subj "/CN=kube-admin"
	openssl x509 -req -in admin.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out admin.pem -days 365
}

