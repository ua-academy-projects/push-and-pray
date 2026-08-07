#!/bin/bash
set -e
ROLE="$1"

apt-get install -y rsyslog-gnutls    # provides the gtls driver

mkdir -p /etc/ssl/rsyslog
mv /tmp/CA.pem /tmp/${ROLE}-key.pem /tmp/${ROLE}-cert.pem /etc/ssl/rsyslog/
chown root:root /etc/ssl/rsyslog/*
chmod 600 /etc/ssl/rsyslog/${ROLE}-key.pem
chmod 644 /etc/ssl/rsyslog/CA.pem /etc/ssl/rsyslog/${ROLE}-cert.pem
mv /tmp/01-${ROLE}.conf /etc/rsyslog.d/
systemctl restart rsyslog