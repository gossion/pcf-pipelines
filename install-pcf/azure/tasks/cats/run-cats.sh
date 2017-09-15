#!/bin/bash
set -ex

#TODO: if pcf_ert_domain configured
cd terraform-state
  web_lb_public_ip=$(cat *.tfstate |  jq --raw-output '.modules[] .resources ["azurerm_public_ip.web-lb-public-ip"] .primary .attributes .ip_address')
  pcf_ert_domain="${web_lb_public_ip}.cf.pcfazure.com"
  OPSMAN_DOMAIN_OR_IP_ADDRESS=$(cat *.tfstate |  jq --raw-output '.modules[] .resources ["azurerm_public_ip.opsman-public-ip"] .primary .attributes .ip_address')
cd -

### Function(s) ###

function fn_om_linux_curl {

    local curl_method=${1}
    local curl_path=${2}
    local curl_data=${3}

     curl_cmd="om-linux --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS -k \
            --username \"$pcf_opsman_admin\" \
            --password \"$pcf_opsman_admin_passwd\"  \
            curl \
            --request ${curl_method} \
            --path ${curl_path}"

    if [[ ! -z ${curl_data} ]]; then
       curl_cmd="${curl_cmd} \
            --data '${curl_data}'"
    fi

    echo ${curl_cmd} > /tmp/rqst_cmd.log
    exec_out=$(((eval $curl_cmd | tee /tmp/rqst_stdout.log) 3>&1 1>&2 2>&3 | tee /tmp/rqst_stderr.log) &>/dev/null)

    if [[ $(cat /tmp/rqst_stderr.log | grep "Status:" | awk '{print$2}') != "200" ]]; then
      echo "Error Call Failed ...."
      echo $(cat /tmp/rqst_stderr.log)
      #exit 1
    else
      echo $(cat /tmp/rqst_stdout.log)
    fi
}

function fn_get_uaa_admin_creds {

  guid_cf=$(fn_om_linux_curl "GET" "/api/v0/staged/products" \
              | jq '.[] | select(.type == "cf") | .guid' | tr -d '"' | grep "cf-.*")
  admin_creds_json_path="/api/v0/deployed/products/${guid_cf}/credentials/.uaa.admin_credentials"
  admin_creds_json=$(fn_om_linux_curl "GET" "${admin_creds_json_path}" | jq . )
  echo ${admin_creds_json}

}

function fn_compile_cats {

  local admin_user=${1}
  local admin_password=${2}

  wget https://storage.googleapis.com/golang/go1.9.linux-amd64.tar.gz
  sudo tar -C /usr/local -xzf go*.tar.gz

  # Set Golang Path
  export PATH=$PATH:/usr/local/go/bin

  # Go Get CATs repo
  root_path=$(pwd)
  export GOPATH="${root_path}/goroot"
  mkdir -p goroot/src
  go get -d github.com/cloudfoundry/cf-acceptance-tests
  cd ${GOPATH}/src/github.com/cloudfoundry/cf-acceptance-tests
  ./bin/update_submodules

  # Setup CATs Config
  echo "{
    \"api\": \"api.sys.${pcf_ert_domain}\",
    \"apps_domain\": \"app.${pcf_ert_domain}\",
    \"admin_user\": \"${admin_user}\",
    \"admin_password\": \"${admin_password}\",
    \"skip_ssl_validation\": true,
    \"skip_regex\": \"lucid64\",
    \"skip_diego_unsupported_tests\": true,
    \"artifacts_directory\": \"${root_path/pipeline-metadata}/\",
    \"java_buildpack_name\": \"java_buildpack_offline\",
    \"backend\": \"diego\",
    \"use_http\": false,
    \"enable_color\": true,
    \"include_apps\": true,
    \"include_backend_compatibility\": true,
    \"include_detect\": true,
    \"include_internet_dependent\": true,
    \"include_route_services\": true,
    \"include_routing\": true,
    \"include_zipkin\": true,
    \"include_ssh\": true,
    \"include_security_groups\": true,
    \"include_services\": true,
    \"include_v3\": true
  }" > integration_config.json

  export CONFIG=$PWD/integration_config.json

  echo "CATs CONFIG="
  cat $CONFIG | jq .
}

### Main Logic ###

 # Prep CATs
 uaa_admin_user=$(fn_get_uaa_admin_creds | jq .credential.value.identity | tr -d '"')
 uaa_admin_password=$(fn_get_uaa_admin_creds | jq .credential.value.password | tr -d '"')

 fn_compile_cats "${uaa_admin_user}" "${uaa_admin_password}"

 # Run CATs
 ./bin/test
