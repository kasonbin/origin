#!/bin/bash
source "$(dirname "${BASH_SOURCE}")/../../hack/lib/init.sh"
os::util::environment::setup_all_server_vars "test-extended/clusterup"

os::util::ensure::built_binary_exists 'oc'
os::util::environment::use_sudo
os::util::environment::setup_time_vars

function cleanup() {
    return_code=$?
    os::test::junit::generate_report
    os::cleanup::all
    os::util::describe_return_code "${return_code}"
    exit "${return_code}"
}
trap "cleanup" EXIT

function os::test::extended::clusterup::make_base_dir () {
    local path=${1}
    base_dir="${BASE_DIR}/${path}/openshift.local.clusterup"
    mkdir -p ${base_dir}
    echo "${base_dir}"
}

function os::test::extended::clusterup::archive_base_dirs () {
    os::log::info "Archiving all base directories to ${ARTIFACT_DIR}/clusterup ..."
    mkdir -p ${ARTIFACT_DIR}/clusterup
	local sudo="${USE_SUDO:+sudo}"
    ${sudo} cp --recursive ${BASE_DIR}/ ${ARTIFACT_DIR}/clusterup/
}

function os::test::extended::clusterup::run_test () {
    local test="${1}"
    local funcname="os::test::extended::clusterup::${test}"
    local global_home="${HOME}"
    os::log::info "starting test -- ${test}"

    os::test::junit::declare_suite_start "extended/clusterup/${test}"

    local test_home="${ARTIFACT_DIR}/${test}/home"
    mkdir -p "${test_home}"
    export HOME="${test_home}"
    pushd "${HOME}" &> /dev/null
    os::log::info "Using ${HOME} as home directory"
    ${funcname} ${2}
    popd &> /dev/null
    export HOME="${global_home}"

    os::log::info "cluster up -- ${test}: ok"
    os::test::junit::declare_suite_end
}

function os::test::extended::clusterup::junit_cleanup() {
    # TODO(skuznets): un-hack this nonsense once traps are in a better state
    if [[ -n "${JUNIT_REPORT_OUTPUT:-}" ]]; then
      # get the jUnit output file into a workable state in case we crashed in the middle of testing something
      os::test::junit::reconcile_output

      # check that we didn't mangle jUnit output
      os::test::junit::check_test_counters

      # use the junitreport tool to generate us a report
      os::util::ensure::built_binary_exists 'junitreport'

      cat "${JUNIT_REPORT_OUTPUT}" "${junit_gssapi_output}" \
        | junitreport --type oscmd                          \
                      --suites nested                       \
                      --roots github.com/openshift/origin   \
                      --output "${ARTIFACT_DIR}/report.xml"
      cat "${ARTIFACT_DIR}/report.xml" | junitreport summarize
    fi
}

function os::test::extended::clusterup::cleanup () {
    os::log::info "Cleaning up cluster"
    oc cluster down
}

function os::test::extended::clusterup::cleanup_func () {
    local test="${1:-}"
    test_cleanup="os::test::extended::clusterup::${test}_cleanup"
    if [[ "$(type -t ${test_cleanup})" == "function" ]]; then
        echo "${test_cleanup}"
    else
        echo "os::test::extended::clusterup::cleanup"
    fi
}

function os::test::extended::clusterup::standard_test () {
    arg=$@
    os::cmd::expect_success "oc cluster up $arg"
}


# Test with host dirs specified
function os::test::extended::clusterup::internal::hostdirs () {
    local base_dir
    base_dir=$(os::test::extended::clusterup::make_base_dir "hostdirs")

    os::test::extended::clusterup::standard_test \
        --base-dir="${base_dir}" \
        --tag="$ORIGIN_COMMIT" \
        ${@}

	local sudo="${USE_SUDO:+sudo}"
    os::cmd::expect_success "${sudo} ls ${base_dir}/kube-apiserver/master-config.yaml"
    os::cmd::expect_success "${sudo} ls ${base_dir}/etcd/member"
}

# Tests the simplest case, no arguments specified
function os::test::extended::clusterup::noargs () {
    local base_dir
    base_dir=$(os::test::extended::clusterup::make_base_dir "noargs")

    os::test::extended::clusterup::standard_test \
      --base-dir=${base_dir} \
      --tag="$ORIGIN_COMMIT" \
      --loglevel=4 \
      ${@}
}

# Test the usage of --enable flag
function os::test::extended::clusterup::enable () {
    local base_dir
    base_dir=$(os::test::extended::clusterup::make_base_dir "enable")
    os::cmd::expect_success "oc cluster up --loglevel=4 --base-dir=${base_dir} --tag=${ORIGIN_COMMIT} --enable=* --write-config"
    os::cmd::expect_failure_and_text "oc cluster up --loglevel=4 --base-dir=${base_dir} --tag=${ORIGIN_COMMIT} --enable=foo" 'use cluster add instead'
}

# Tests creating a cluster with specific host directories
function os::test::extended::clusterup::hostdirs () {
    local base_dir
    base_dir=$(os::test::extended::clusterup::make_base_dir "hostdirs")

    # need to set up the config dir with the proper content
    oc cluster up \
        --base-dir="${base_dir}/config" \
        --tag="$ORIGIN_COMMIT" \
        --write-config

    BASE_DIR="${base_dir}" os::test::extended::clusterup::internal::hostdirs ${@}
}

# Tests creating a cluster with a public hostname
function os::test::extended::clusterup::publichostname () {
    local base_dir
    base_dir=$(os::test::extended::clusterup::make_base_dir "public_hostname")

    # need to set up the config dir with the proper content
    oc cluster up \
        --public-hostname="myserver.127.0.0.1.nip.io" \
        --base-dir="${base_dir}" \
        --tag="$ORIGIN_COMMIT" \
        --write-config

    BASE_DIR="${base_dir}" os::test::extended::clusterup::standard_test \
        --public-hostname="myserver.127.0.0.1.nip.io" \
        --base-dir="${base_dir}" \
        --tag="$ORIGIN_COMMIT" \
        ${@}
    os::cmd::expect_success_and_text "cat ${base_dir}/kube-apiserver/master-config.yaml" "masterPublicURL.*myserver\.127\.0\.0\.1\.nip\.io"
}

# Tests creating a cluster with a numeric public hostname
function os::test::extended::clusterup::numerichostname () {
    local base_dir
    base_dir=$(os::test::extended::clusterup::make_base_dir "numeric_public_hostname")

    # need to set up the config dir with the proper content
    oc cluster up \
        --public-hostname="127.0.0.1" \
        --base-dir="${base_dir}/config" \
        --tag="$ORIGIN_COMMIT" \
        --write-config

    os::test::extended::clusterup::standard_test \
        --public-hostname="127.0.0.1" \
        --base-dir="${base_dir}" \
        --tag="$ORIGIN_COMMIT" \
        ${@}
    os::cmd::expect_success_and_text "cat ${base_dir}/kube-apiserver/master-config.yaml" "masterPublicURL.*127\.0\.0\.1"
}

# Verifies that a service can be accessed by a peer pod
# and by the pod running the service
function os::test::extended::clusterup::svcaccess () {
    local base_dir
    base_dir=$(os::test::extended::clusterup::make_base_dir "service_access")

    arg=$@
    os::cmd::expect_success "oc cluster up --base-dir=${base_dir} $arg"
    os::cmd::expect_success "oc create -f ${OS_ROOT}/examples/gitserver/gitserver-persistent.yaml"
	os::cmd::try_until_text "oc get endpoints git -o jsonpath='{ .subsets[*].ports[?(@.port==8080)].port }'" "8080" $(( 10*minute )) 1
    # Test that a service can be accessed from a peer pod
    sleep 10
    os::cmd::expect_success "timeout 20s oc run peer --image=openshift/origin-gitserver:latest --attach --restart=Never --command -- curl http://git:8080/_/healthz"

    # Test that a service can be accessed from the same pod
    # This doesn't work in any cluster i've tried, not sure why but it's not a cluster up issue.
    #os::cmd::expect_success "timeout 2m oc rsh dc/git curl http://git:8080/_/healthz"
}

# Verifies that cluster up can start when a process is bound
# to the loopback interface with tcp port 53
function os::test::extended::clusterup::portinuse () {
    local base_dir
    base_dir=$(os::test::extended::clusterup::make_base_dir "port_in_use")

    # Start listening on the host's 127.0.0.1 interface, port 53
    os::cmd::expect_success "docker run -d --name=port53 --entrypoint=/bin/bash --net=host openshift/origin-gitserver:latest -c \"socat TCP-LISTEN:53,bind=127.0.0.1,fork SYSTEM:'echo hello'\""
    arg=$@
    os::cmd::expect_success "oc cluster up --base-dir=${base_dir} $arg"
}

function os::test::extended::clusterup::portinuse_cleanup () {
    os::test::extended::clusterup::cleanup
    docker rm -f port53
}


readonly default_tests=(
    "noargs"
    "hostdirs"
    "publichostname"
    "numerichostname"
    "portinuse"
)

# BASE_DIR is the base directory used by all tests. This must be a /tmp directory to avoid
# problems when mounting the PVC into pods created by cluster up (like registry...).
BASE_DIR="$(mktemp -d)/clusterup"

ORIGIN_COMMIT=${ORIGIN_COMMIT:-latest}

# run each test with each of these set of additional args.  Primarily
# intended to run the tests against different cluster versions.
readonly extra_args=(
    # Test the previous OCP release
    # TODO - enable this once v3.9 ships, v3.7 didn't have a TSB image so it's
    # annoying to test.
    #"--loglevel=4 --image=registry.access.redhat.com/openshift3/ose --tag=v3.7"

    # Test the previous origin release
    # TODO - enable this once oc cluster up v3.9 supports modifiying cluster
    # roles on a 3.7 cluster image (https://github.com/openshift/origin/issues/17867)
    # "--loglevel=4 --image=docker.io/openshift/origin --tag=v3.7.0"

    # Test the current published release
    # disabling this based on irc with clayton.  This is more strict than openshift-ansible.
    #"--loglevel=4"  # can't be empty, so pass something benign

    # Test the code being delivered
    "--loglevel=4 --server-loglevel=4 --tag=${ORIGIN_COMMIT}"

)
tests=("${1:-"${default_tests[@]}"}")

echo "Running cluster up tests using tag $ORIGIN_COMMIT"

# Ensure that KUBECONFIG is not set
unset KUBECONFIG
for test in "${tests[@]}"; do
    for extra_arg in "${extra_args[@]}"; do
        cleanup_func=$("os::test::extended::clusterup::cleanup_func" "${test}")
        # trap "${cleanup_func}; os::test::extended::clusterup::junit_cleanup" EXIT
        os::test::extended::clusterup::run_test "${test}" "${extra_arg}"
        # trap - EXIT
        ${cleanup_func}
    done
done

# TODO: Make this part of the cleanup
os::test::extended::clusterup::archive_base_dirs

# TODO: Why is this disabled?
# os::test::extended::clusterup::junit_cleanup
