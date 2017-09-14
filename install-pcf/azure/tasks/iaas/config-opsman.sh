#!/bin/bash
set -ex

echo "=============================================================================================="
echo "Configuring OpsManager @ https://opsman.${PCF_ERT_DOMAIN} ..."
echo "=============================================================================================="

cd terraform-state
  opsman_public_ip=$(cat *.tfstate |  jq --raw-output '.modules[] .resources ["azurerm_public_ip.opsman-public-ip"] .primary .attributes .ip_address')
cd -

#Configure Opsman
om-linux --target https://${opsman_public_ip} -k \
  configure-authentication \
  --username "${PCF_OPSMAN_ADMIN}" \
  --password "${PCF_OPSMAN_ADMIN_PASSWORD}" \
  --decryption-passphrase "${PCF_OPSMAN_ADMIN_PASSWORD}"
