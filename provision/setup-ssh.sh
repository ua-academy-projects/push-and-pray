#!/usr/bin/env bash

USER_NAME="$1"
PUB_KEY="$2"

if ! id "$USER_NAME" > /dev/null 2>&1; then
    sudo useradd -m -s /bin/bash "$USER_NAME"
fi
sudo usermod -p '*' "$USER_NAME"

sudo mkdir -p "/home/$USER_NAME/.ssh"
echo "$PUB_KEY" | sudo tee "/home/$USER_NAME/.ssh/authorized_keys" > /dev/null
sudo chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.ssh"
sudo chmod 700 "/home/$USER_NAME/.ssh"
sudo chmod 600 "/home/$USER_NAME/.ssh/authorized_keys"

sudo sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
