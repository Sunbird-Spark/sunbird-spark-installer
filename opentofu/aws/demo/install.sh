#!/bin/bash
set -euo pipefail

echo -e "\nPlease ensure you have updated all the mandatory variables as mentioned in the documentation."
echo "The installation will fail if any of the mandatory variables are missing."
echo "Press Enter to continue..."
read -r

environment=$(basename "$(pwd)")

function create_tf_backend() {
    echo -e "Creating terraform state backend"
    bash create_tf_backend.sh
}

function backup_configs() {
    timestamp=$(date +%d%m%y_%H%M%S)
    echo -e "\nBackup existing config files if they exist"
    mkdir -p ~/.kube
    mv ~/.kube/config ~/.kube/config.$timestamp || true
    mkdir -p ~/.config/rclone
    mv ~/.config/rclone/rclone.conf ~/.config/rclone/rclone.conf.$timestamp || true
    export KUBECONFIG=~/.kube/config
}

function create_tf_resources() {
    source tf.sh
    echo -e "\nCreating resources on AWS cloud"
    
    # Deploy modules in order
    modules=("network" "storage" "random_passwords" "eks" "output-file")
    
    for module in "${modules[@]}"; do
        echo -e "\n=== Deploying $module ==="
        cd "$module"
        terragrunt init -upgrade -reconfigure
        terragrunt apply -auto-approve
        cd ..
    done
    
    chmod 600 ~/.kube/config 2>/dev/null || true
}
function certificate_keys() {
    #  # If keys already present in global-values.yaml → skip writing
    if grep -q -E '^[[:space:]]*CERTIFICATE_PRIVATE_KEY:' ../terraform/aws/$environment/global-values.yaml 2>/dev/null; then
        echo "Certificate keys already present — skipping generation and write."
        return
    fi
    # Generate private and public keys using openssl
    echo "Creation of RSA keys for certificate signing"
    openssl genrsa -out ../terraform/aws/$environment/certkey.pem;
    openssl rsa -in ../terraform/aws/$environment/certkey.pem -pubout -out ../terraform/aws/$environment/certpubkey.pem;
    CERTPRIVATEKEY=$(sed 's/KEY-----/KEY-----\\n/g' ../terraform/aws/$environment/certkey.pem | sed 's/-----END/\\n-----END/g' | awk '{printf("%s",$0)}')
    CERTPUBLICKEY=$(sed 's/KEY-----/KEY-----\\n/g' ../terraform/aws/$environment/certpubkey.pem | sed 's/-----END/\\n-----END/g' | awk '{printf("%s",$0)}')
    CERTIFICATESIGNPRKEY=$(sed 's/BEGIN PRIVATE KEY-----/BEGIN PRIVATE KEY-----\\\\n/g' ../terraform/aws/$environment/certkey.pem | sed 's/-----END PRIVATE KEY/\\\\n-----END PRIVATE KEY/g' | awk '{printf("%s",$0)}')
    CERTIFICATESIGNPUKEY=$(sed 's/BEGIN PUBLIC KEY-----/BEGIN PUBLIC KEY-----\\\\n/g' ../terraform/aws/$environment/certpubkey.pem | sed 's/-----END PUBLIC KEY/\\\\n-----END PUBLIC KEY/g' | awk '{printf("%s",$0)}')
    printf "\n" >> ../terraform/aws/$environment/global-values.yaml
    echo "  CERTIFICATE_PRIVATE_KEY: \"$CERTPRIVATEKEY\"" >> ../terraform/aws/$environment/global-values.yaml
    echo "  CERTIFICATE_PUBLIC_KEY: \"$CERTPUBLICKEY\"" >> ../terraform/aws/$environment/global-values.yaml
    echo "  CERTIFICATESIGN_PRIVATE_KEY: \"$CERTIFICATESIGNPRKEY\"" >> ../terraform/aws/$environment/global-values.yaml
    echo "  CERTIFICATESIGN_PUBLIC_KEY: \"$CERTIFICATESIGNPUKEY\"" >> ../terraform/aws/$environment/global-values.yaml
}


function certificate_config() {
    local script_dir exec_deploy
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    exec_deploy="knowledge-mw"
    if kubectl -n sunbird get deploy nodebb >/dev/null 2>&1; then
        exec_deploy="nodebb"
    fi

    echo "Configuring Certificate keys (via ${exec_deploy})"
    CERTKEY=$(kubectl -n sunbird exec "deploy/${exec_deploy}" -- curl -s --location --request POST 'http://registry-service:8081/api/v1/PublicKey/search' --header 'Content-Type: application/json' --data-raw '{ "filters": {}}' | jq -r '.[] | .value // empty')
    # Inject cert keys to the service if its not available
    if [ -z "$CERTKEY" ]; then
        echo "Certificate RSA public key not available"
        CERTPUBKEY=$(awk -F'"' '/CERTIFICATE_PUBLIC_KEY/{print $2}' "$script_dir/global-values.yaml")
        curl_data="curl --location --request POST 'http://registry-service:8081/api/v1/PublicKey' --header 'Content-Type: application/json' --data-raw '{\"value\":\"$CERTPUBKEY\"}'"
        echo "kubectl -n sunbird exec deploy/${exec_deploy} -- $curl_data" | sh -
    else
        echo "Certificate public key already configured in registry"
    fi
}
function install_component() {
    export KUBECONFIG="${HOME}/.kube/config"
    # Source AWS credentials so EKS auth works when called standalone
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$script_dir/tf.sh" ]; then
        source "$script_dir/tf.sh"
    fi
    # Fetch kubeconfig from EKS if not already configured
    local building_block env_name cluster_name
    building_block=$(grep 'building_block:' "$script_dir/global-values.yaml" | awk '{print $2}' | tr -d '"')
    env_name=$(grep '^  env:' "$script_dir/global-values.yaml" | awk '{print $2}' | tr -d '"')
    cluster_name="${building_block}-${env_name}"
    echo "Fetching kubeconfig for EKS cluster: ${cluster_name}"
    aws eks update-kubeconfig --region "${AWS_REGION}" --name "${cluster_name}"
    # We need a dummy cm for configmap to start. Later Lernbb will create real one
    kubectl create configmap keycloak-key -n sunbird 2>/dev/null || true
    local current_directory="$(pwd)"
    if [ "$(basename $current_directory)" != "helmcharts" ]; then
        cd ../../../helmcharts 2>/dev/null || true
    fi
    local component="$1"
    if [ ! -d "$component" ] || [ ! -f "$component/Chart.yaml" ]; then
        echo "Error: Helm chart not found at helmcharts/$component (missing directory or Chart.yaml)"
        exit 1
    fi
    kubectl create namespace sunbird 2>/dev/null || true
    kubectl create namespace velero 2>/dev/null || true
    kubectl create namespace volume-autoscaler 2>/dev/null || true
    kubectl create namespace nlweb 2>/dev/null || true

    echo -e "\nInstalling $component"
    local ed_values_flag=""
    if [ -f "$component/ed-values.yaml" ]; then
        ed_values_flag="-f $component/ed-values.yaml --wait --wait-for-jobs"
    fi
    ### Generate the key pair required for certificate template
      if [ $component = "learnbb" ]; then
        if kubectl get job keycloak-kids-keys -n sunbird >/dev/null 2>&1; then
            echo "Deleting existing job keycloak-kids-keys..."
            kubectl delete job keycloak-kids-keys -n sunbird
        fi

        if [ -f "certkey.pem" ] && [ -f "certpubkey.pem" ]; then
            echo "Certificate keys are already created. Skipping the keys creation..."
        else
            certificate_keys
        fi
      fi
    helm upgrade --install "$component" "$component" --namespace sunbird -f "$component/values.yaml" \
        $ed_values_flag \
        -f images.yaml \
        -f "global-resources.yaml" \
        -f "$script_dir/global-values.yaml" \
        -f "$script_dir/global-cloud-values.yaml" --timeout 30m --debug
}

function install_helm_components() {
    components=("monitoring" "edbb" "learnbb" "knowledgebb" "obsrvbb" "inquirybb" "additional")
    for component in "${components[@]}"; do
        install_component "$component"
    done
}

function post_install_nodebb_plugins() {
    echo ">> Waiting for NodeBB deployment to be ready..."
    kubectl rollout status deployment nodebb -n sunbird --timeout=300s

    echo ">> Activating NodeBB plugins..."
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-create-forum
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-sunbird-oidc
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-write-api

    echo ">> Rebuilding NodeBB to apply plugin changes..."
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb build

    echo ">> Restarting NodeBB..."
    kubectl delete pod -n sunbird -l app.kubernetes.io/name=nodebb

    echo "NodeBB plugins are activated, built, and NodeBB has been restarted."
}

function get_domain_name() {
    local script_dir domain
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if kubectl -n sunbird get cm lms-env >/dev/null 2>&1; then
        domain=$(kubectl get cm -n sunbird lms-env -ojsonpath='{.data.sunbird_web_url}')
    elif kubectl -n sunbird get cm cert-env >/dev/null 2>&1; then
        domain=$(kubectl get cm -n sunbird cert-env -ojsonpath='{.data.sunbird_cert_domain_url}')
    elif kubectl -n sunbird get cm player-env >/dev/null 2>&1; then
        domain=$(kubectl get cm -n sunbird player-env -ojsonpath='{.data.DOMAIN_URL}')
    else
        domain=$(grep '^  domain:' "$script_dir/global-values.yaml" | awk '{print $2}' | tr -d '"')
    fi
    domain="${domain#https://}"
    domain="${domain#http://}"
    domain="${domain%/}"
    echo "$domain"
}

function get_load_balancer_hostname() {
    kubectl get svc -n sunbird nginx-public-ingress -ojsonpath='{.status.loadBalancer.ingress[0].hostname}'
}

function get_load_balancer_ips() {
    local lb_ip lb_host
    lb_ip=$(kubectl get svc -n sunbird nginx-public-ingress -ojsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ -n "$lb_ip" ]; then
        echo "$lb_ip"
        return
    fi
    lb_host=$(get_load_balancer_hostname)
    if [ -n "$lb_host" ]; then
        dig +short "$lb_host" 2>/dev/null | grep -E '^[0-9.]+$' | sort -u
    fi
}

function dns_mapping_propagated() {
    local domain="$1" lb_host="$2"
    local domain_cname domain_ip lb_ip

    domain_cname=$(dig +short CNAME "$domain" 2>/dev/null | head -1 | sed 's/\.$//')
    if [ -n "$lb_host" ] && [ "$domain_cname" = "$lb_host" ]; then
        return 0
    fi

    while IFS= read -r domain_ip; do
        [ -z "$domain_ip" ] && continue
        while IFS= read -r lb_ip; do
            [ -z "$lb_ip" ] && continue
            if [ "$domain_ip" = "$lb_ip" ]; then
                return 0
            fi
        done < <(get_load_balancer_ips)
    done < <(dig +short "$domain" 2>/dev/null | grep -E '^[0-9.]+$')

    return 1
}

function dns_mapping() {
    domain_name=$(get_domain_name)
    LB_HOST=$(get_load_balancer_hostname)
    mapfile -t LB_IPS < <(get_load_balancer_ips)
    PUBLIC_IP="${LB_IPS[0]:-}"

    local timeout=$((SECONDS + 1200))
    local check_interval=10

    if [ -z "$domain_name" ] || { [ -z "$PUBLIC_IP" ] && [ -z "$LB_HOST" ]; }; then
        echo "Could not resolve domain name or load balancer address."
        echo "  domain: ${domain_name:-<empty>}"
        echo "  load balancer: ${LB_HOST:-<empty>}"
        echo "  load balancer IP: ${PUBLIC_IP:-<empty>}"
        exit 1
    fi

    echo ""
    echo "Add/update DNS for ${domain_name}:"
    if [ -n "$LB_HOST" ]; then
        echo "  Recommended: CNAME -> ${LB_HOST}"
        echo "  Load balancer IP(s): ${LB_IPS[*]}"
    else
        echo "  A record -> ${PUBLIC_IP}"
    fi
    echo "Waiting up to 20 minutes for propagation."

    while [ $SECONDS -lt $timeout ]; do
        if dns_mapping_propagated "$domain_name" "$LB_HOST"; then
            echo ""
            echo "DNS mapping has propagated successfully."
            return
        fi
        current_ip=$(dig +short "$domain_name" 2>/dev/null | grep -E '^[0-9.]+$' | head -1)
        echo "DNS mapping is still propagating (${domain_name} -> ${current_ip:-unknown}; expected CNAME ${LB_HOST:-n/a} or IP ${LB_IPS[*]}). Retrying in ${check_interval}s..."
        sleep $check_interval
    done

    echo "Timed out after 20 minutes. DNS mapping may not have propagated successfully. Rerun the following staging post DNS mapping propagation."
    echo "./install.sh dns_mapping"
    echo "./install.sh generate_postman_env"
    echo "./install.sh run_post_install"
}

function kubectl_cm_value() {
    local val cm key
    while [ $# -ge 2 ]; do
        cm="$1"
        key="$2"
        shift 2
        if kubectl -n sunbird get cm "$cm" >/dev/null 2>&1; then
            val=$(kubectl get cm -n sunbird "$cm" -ojsonpath="{.data.${key}}" 2>/dev/null)
            if [ -n "$val" ]; then
                echo "$val"
                return 0
            fi
        fi
    done
    return 1
}

function generate_postman_env() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ "$(basename "$(pwd)")" != "$environment" ]; then
        cd "$script_dir" 2>/dev/null || true
    fi

    domain_name=$(kubectl_cm_value \
        lms-env sunbird_web_url \
        lern-env sunbird_web_url \
        player-env DOMAIN_URL \
        cert-env sunbird_cert_domain_url) || domain_name=$(get_domain_name)
    domain_name="${domain_name#https://}"
    domain_name="${domain_name#http://}"
    domain_name="${domain_name%/}"

    blob_store_path=$(kubectl_cm_value \
        player-env sunbird_public_storage_account_name \
        lern-env cloud_storage_base_url) || blob_store_path=""
    blob_store_path=$(echo "$blob_store_path" | sed 's|/*$||')

    public_container_name=$(kubectl_cm_value \
        player-env cloud_storage_resourceBundle_bucketname \
        lern-env sunbird_content_cloud_storage_container \
        cert-env PUBLIC_CONTAINER_NAME) || public_container_name=""

    api_key=$(kubectl_cm_value \
        player-env sunbird_api_auth_token \
        lern-env sunbird_authorization) || api_key=""

    keycloak_secret=$(kubectl_cm_value \
        player-env sunbird_portal_session_secret \
        player-env SUNBIRD_SESSION_SECRET) || keycloak_secret=""

    keycloak_admin=$(kubectl_cm_value \
        userorg-env sunbird_sso_username \
        lern-env sunbird_sso_username) || keycloak_admin=""

    keycloak_password=$(kubectl_cm_value \
        userorg-env sunbird_sso_password \
        lern-env sunbird_sso_password) || keycloak_password=""

    generated_uuid=$(uuidgen)
    temp_file=$(mktemp)
    cp postman.env.json "${temp_file}"
    sed -e "s|REPLACE_WITH_DOMAIN|${domain_name}|g" \
        -e "s|REPLACE_WITH_APIKEY|${api_key}|g" \
        -e "s|REPLACE_WITH_SECRET|${keycloak_secret}|g" \
        -e "s|REPLACE_WITH_KEYCLOAK_ADMIN|${keycloak_admin}|g" \
        -e "s|REPLACE_WITH_KEYCLOAK_PASSWORD|${keycloak_password}|g" \
        -e "s|GENERATE_UUID|${generated_uuid}|g" \
        -e "s|BLOB_STORE_PATH|${blob_store_path}|g" \
        -e "s|PUBLIC_CONTAINER_NAME|${public_container_name}|g" \
        "${temp_file}" >"env.json"

    echo -e "A env.json file is created in this directory: ${script_dir}"
    echo "Import the env.json file into postman to invoke other APIs"
}

function restart_workloads_using_keys() {
    echo -e "\nRestart workloads using keycloak keys and wait for them to start..."
    kubectl rollout restart deployment -n sunbird neo4j knowledge-mw player report content adminutil cert-registry groups userorg lms notification registry analytics
    kubectl rollout status deployment -n sunbird neo4j knowledge-mw player report content adminutil cert-registry groups userorg lms notification registry analytics
    echo -e "\nWaiting for all pods to start"
}

function get_postman_collection_file() {
    local script_dir repo_root candidates f
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    repo_root="$(cd "$script_dir/../../.." && pwd)"
    candidates=(
        "$repo_root/postman-collection/collection${RELEASE}.json"
        "$repo_root/postman-collection/sunbird-spark-collection-v1.json"
    )
    for f in "${candidates[@]}"; do
        if [ -f "$f" ]; then
            echo "$f"
            return 0
        fi
    done
    f=$(find "$repo_root/postman-collection" -maxdepth 1 -name '*.json' -type f 2>/dev/null | head -1)
    if [ -n "$f" ]; then
        echo "$f"
        return 0
    fi
    local download_url="https://raw.githubusercontent.com/Sunbird-Spark/sunbird-spark-installer/main/postman-collection/sunbird-spark-collection-v1.json"
    local dest="$repo_root/postman-collection/sunbird-spark-collection-v1.json"
    echo "Postman collection not found locally; downloading from Sunbird-Spark/sunbird-spark-installer..."
    mkdir -p "$repo_root/postman-collection"
    if curl -fsSL -o "$dest" "$download_url"; then
        echo "$dest"
        return 0
    fi
    echo "No Postman collection found under $repo_root/postman-collection" >&2
    return 1
}

function run_postman_collection() {
    local collection_name="$1"
    if command -v newman >/dev/null 2>&1; then
        newman run "$collection_name" \
            --environment env.json \
            --delay-request 500 \
            --timeout-request 30000 \
            --insecure \
            --bail
        return $?
    fi
    if command -v npx >/dev/null 2>&1; then
        npx --yes newman run "$collection_name" \
            --environment env.json \
            --delay-request 500 \
            --timeout-request 30000 \
            --insecure \
            --bail
        return $?
    fi
    if command -v xvfb-run >/dev/null 2>&1; then
        ELECTRON_DISABLE_GPU=1 xvfb-run -a postman collection run "$collection_name" \
            --environment env.json \
            --delay-request 500 \
            --bail \
            --insecure
        return $?
    fi
    echo "No headless Postman runner found. Install Newman (recommended on servers without a display):" >&2
    echo "  sudo apt install -y npm && sudo npm install -g newman" >&2
    echo "Or install xvfb for the Postman snap: sudo apt install -y xvfb" >&2
    return 1
}

function run_post_install() {
    local script_dir collection_file collection_name
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ "$(basename "$(pwd)")" != "$environment" ]; then
        cd "$script_dir" 2>/dev/null || true
    fi
    check_pod_status
    echo "Starting post install..."
    collection_file=$(get_postman_collection_file) || exit 1
    collection_name=$(basename "$collection_file")
    cp "$collection_file" .
    run_postman_collection "$collection_name"
}

function ensure_ed_client_forms_collections() {
    local repo_root="$1"
    local ed_dir="$repo_root/postman-collection/ED-${RELEASE}"
    local base_url="https://raw.githubusercontent.com/project-sunbird/sunbird-ed-installer/main/postman-collection/ED-${RELEASE}"
    local files=(
        Easy-Installer-7.0-Question-Set-Editor.postman_collection.json
        Easy-Installer-7.0-editor-forms.postman_collection.json
        Easy-Installer-7.0-mobile.postman_collection.json
        Easy-Installer-7.0-portal.postman_collection.json
        Easy-Installer-7.0.postman_collection.json
    )
    if [ -d "$ed_dir" ] && find "$ed_dir" -maxdepth 1 -name '*.json' -print -quit | grep -q .; then
        return 0
    fi
    echo "ED-${RELEASE} collections not found locally; downloading from project-sunbird/sunbird-ed-installer..."
    mkdir -p "$ed_dir"
    local f
    for f in "${files[@]}"; do
        curl -fsSL -o "$ed_dir/$f" "$base_url/$f"
    done
}

function create_client_forms() {
    local script_dir repo_root ed_dir collection_file
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    repo_root="$(cd "$script_dir/../../.." && pwd)"
    if [ "$(basename "$(pwd)")" != "$environment" ]; then
        cd "$script_dir" 2>/dev/null || true
    fi
    if [ ! -f env.json ]; then
        echo "env.json not found. Run ./install.sh generate_postman_env first." >&2
        return 1
    fi
    ensure_ed_client_forms_collections "$repo_root" || {
        echo "Failed to obtain ED-${RELEASE} client form collections." >&2
        return 1
    }
    ed_dir="$repo_root/postman-collection/ED-${RELEASE}"
    cp -rf "$ed_dir" .
    check_pod_status
    echo "Starting client forms (ED-${RELEASE})..."
    for collection_file in "ED-${RELEASE}"/*.json; do
        echo "Creating client forms in.. $collection_file"
        run_postman_collection "$collection_file" || return 1
    done
}

function cleanworkspace() {
        rm  certkey.pem certpubkey.pem
        sed -i '/CERTIFICATE_PRIVATE_KEY:/d' global-values.yaml
        sed -i '/CERTIFICATE_PUBLIC_KEY:/d' global-values.yaml
        sed -i '/CERTIFICATESIGN_PRIVATE_KEY:/d' global-values.yaml
        sed -i '/CERTIFICATESIGN_PUBLIC_KEY:/d' global-values.yaml
        echo "cleanup completed"
}
function destroy_tf_resources() {
    source tf.sh
    cleanworkspace
    echo -e "Destroying resources on AWS cloud"
    
    # Destroy modules in reverse order
    modules=("output-file" "eks" "random_passwords" "storage" "network")
    
    for module in "${modules[@]}"; do
        echo -e "\n=== Destroying $module ==="
        cd "$module"
        terragrunt destroy -auto-approve || true
        cd ..
    done
}

function invoke_functions() {
    for func in "$@"; do
        $func
    done
}

function check_pod_status() {
    echo -e "\nRemove any orphaned pods if they exist."
    kubectl get pod -n sunbird --no-headers 2>/dev/null | grep -v Completed | grep -v Running | awk '{print $1}' | xargs -r -I {} kubectl delete -n sunbird pod {} 2>/dev/null || true
    local timeout=$((SECONDS + 600))
    consecutive_runs=0
    echo "Ensure the post are stable for 100 seconds"
    while [ $SECONDS -lt $timeout ]; do
        if ! kubectl get pods --no-headers -n sunbird | grep -v Running | grep -v Completed; then
            echo "All pods are running successfully."
            break
        else
            ((consecutive_runs++))
        fi

        if [ $consecutive_runs -ge 10 ]; then
            echo "Timed out after 10 tries. Some pods are still not running successfully. Check the crashing pod logs and resolve the issues. Once pods are running successfully, re-reun this script as below:"
            echo "./install.sh run_post_install"
            exit
        fi

        echo "Number of crashing pods found. Countdown to 10"
        sleep 10
    done
    echo "All pods are running successfully."
}

RELEASE="release700"
POSTMAN_COLLECTION_LINK="https://api.postman.com/collections/5338608-e28d5510-20d5-466e-a9ad-3fcf59ea9f96?access_key=PMAT-01HMV5SB2ZPXCGNKD74J7ARKRQ"
CERTPUBLICKEY=""
CERTPRIVATEKEY=""


if [ $# -eq 0 ]; then
    create_tf_backend
    backup_configs
    create_tf_resources
    cd ../../../helmcharts
    install_helm_components
    cd ../opentofu/aws/template
    post_install_nodebb_plugins
    restart_workloads_using_keys
    certificate_config
    dns_mapping
    generate_postman_env
    run_post_install
    create_client_forms
else
    case "$1" in
    "create_tf_backend")
        create_tf_backend
        ;;
    "create_tf_resources")
        create_tf_resources
        ;;
    "generate_postman_env")
        generate_postman_env
        ;;
    "dns_mapping")
        dns_mapping
        ;;
    "install_component")
        shift
        if [ $# -eq 0 ]; then
            echo "Usage: ./install.sh install_component <component_name>"
            echo "Available components: monitoring edbb learnbb knowledgebb obsrvbb inquirybb additional"
            exit 1
        fi
        install_component "$1"
        ;;
    "install_helm_components")
        install_helm_components
        ;;
    "run_post_install")
        run_post_install
        ;;
    "destroy_tf_resources")
        destroy_tf_resources
        ;;
    "certificate_config")
        certificate_config
        ;;
    "create_client_forms")
        create_client_forms
        ;;
    *)
        invoke_functions "$@"
        ;;
    esac
fi
