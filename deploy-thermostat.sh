#!/bin/bash
# 
# Build and deploy Thermostat on OpenShift
#
#set -x

OC_ARGS=()
HELP_STRING="\nUSAGE: $0 [-s server_url] [-n namespace]
    -s server_url
        Specify the URL of the OpenShift server that will be used to deploy Thermostat.
        If not specified, oc will use its default configuration.
    -n namespace
        Override the default namespace to use for building and deploying Thermostat.\n\n"

print_help() {
  printf "$HELP_STRING"
}

parse_args() {
  local OPTIND
  OPTIND=1
  while getopts ":s:n:" opt ; do
    case "${opt}" in
      s)
        OC_ARGS+=(--server="${OPTARG}")
        ;;
      n)
        OC_ARGS+=(--namespace="${OPTARG}")
        ;;
      :)
        printf "Option '-$OPTARG' requires an argument."
        print_help
        exit 1
        ;;
      *)
        printf "Unexpected option '-${OPTARG}'"
        print_help
        exit 1
        ;;
    esac
  done
}

check_oc_installed() {
  # Check for oc binary in PATH
  if [ -z "${OC:=$(which oc 2>/dev/null)}" ]; then
    printf "%s\n" "OpenShift client tools (oc) not found in PATH" \
    "Please download and install 'oc' from: https://www.openshift.org/download.html" \
    "or in Fedora install the origin-clients RPM" >&2
    exit 1
  fi
}

openshift_login() {
  echo "Logging in to OpenShift"
  "${OC}" "${OC_ARGS[@]}" login 
  if [ $? -ne 0 ]; then
    echo "Failed to log in to OpenShift" >&2
    exit 1
  fi
}

script_directory() {
  # Compute the parent directory. I.e. the (symlink-resolved) location of the
  # currently executing code's directory. See
  # http://stackoverflow.com/a/246128/3561275 for implementation details.
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  echo "$DIR"
}

instantiate_template() {
  local template="$1"
  local component_name="$2"
  "${OC}" "${OC_ARGS[@]}" process -f "${template}" | "${OC}" "${OC_ARGS[@]}" create -f -
  if [ $? -ne 0 ]; then
    echo "Failed to instantiate ${component_name} template" >&2
    exit 1
  fi
}

wait_for_rollout() {
  local deployment_config="$1"
  local component_name="$2"

  # Wait for deployment to rollout
  "${OC}" "${OC_ARGS[@]}" --request-timeout=0 rollout status "dc/${deployment_config}"
  if [ $? -ne 0 ]; then
    echo "${component_name} deployment failed" >&2
    exit 1
  fi
}

follow_build() {
  local build_config="$1"
  local build_name="$2"

  echo "Building ${build_name}..."
  "${OC}" "${OC_ARGS[@]}" logs -f "bc/${build_config}"
  local build_phase=$("${OC}" "${OC_ARGS[@]}" get -o custom-columns=:.status.phase --no-headers builds "${build_config}-1")
  if [ "${build_phase}" != "Complete" ]; then
    local err_msg=$("${OC}" "${OC_ARGS[@]}" get -o custom-columns=:.status.message --no-headers builds "${build_config}-1")
    echo "Build failed for ${build_name}: ${err_msg}" >&2
    exit 1
  fi
  echo "Build for ${build_name} complete"
}

deploy_mongodb() {
  local component_name="MongoDB"
  echo "Deploying ${component_name}..."
  local mongo_template="$(script_directory)/thermostat-mongodb-online-starter.yaml"
  instantiate_template "${mongo_template}" "${component_name}"
  # TODO Follow dc log in background to give better reporting
  wait_for_rollout "thermostat-mongodb-dc" "${component_name}"
  echo "Finished deploying ${component_name}"
}

deploy_gateway_client() {
  local component_name="Web Gateway + Client"
  echo "Building and deploying ${component_name}..."
  local gateway_client_template="$(script_directory)/thermostat-gateway-client-online-starter.yaml"
  instantiate_template "${gateway_client_template}" "${component_name}"
  # Track build logs
  follow_build "thermostat-gateway-bc" "Web Gateway"
  follow_build "thermostat-gateway-client-bc" "Web Client"
  # TODO Follow dc log in background to give better reporting
  wait_for_rollout "thermostat-gateway-client-dc" "${component_name}"
  echo "Finished building and deploying ${component_name}"
}

deploy_agent_test() {
  local component_name="Agent + Test App"
  echo "Building and deploying ${component_name}..."
  local agent_template="$(script_directory)/thermostat-agent-online-starter.yaml"
  instantiate_template "${agent_template}" "${component_name}"
  # Track build logs
  follow_build "thermostat-agent-bc" "Agent"
  follow_build "thermostat-wildfly-testapp-bc" "Test App"
  # TODO Follow dc log in background to give better reporting
  wait_for_rollout "thermostat-wildfly-testapp-dc" "${component_name}"
  echo "Finished building and deploying ${component_name}"
}

print_client_url() {
  echo "Deployment of all Thermostat components succeeded"
  # TODO figure out whether to use HTTP or HTTPS
  local gateway_url="https://$("${OC}" "${OC_ARGS[@]}" get route -o=custom-columns=:.spec.host --no-headers thermostat-gateway-client-route)"
  if [ -z "${gateway_url}" ]; then
    echo "Failed to retrieve URL to web client" >&2
  else
    echo "The web client can be accessed at: ${gateway_url}/web-client/"
    echo "Use credentials 'client':'client-pwd' to log in."
  fi
}

# Parse command line arguments
parse_args "$@"

# Ensure oc binary is installed
check_oc_installed

# Log in to OpenShift server
openshift_login

# Deploy each Thermostat component in order
deploy_mongodb
deploy_gateway_client
deploy_agent_test

# Print success message
print_client_url
