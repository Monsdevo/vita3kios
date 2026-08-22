#!/bin/sh

set -eu

VITA3KIOS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VITA3KIOS_ROOT=$(CDPATH= cd -- "$VITA3KIOS_SCRIPT_DIR/.." && pwd)
. "$VITA3KIOS_SCRIPT_DIR/toolchain-env.sh"

VITA3KIOS_ACTION=${1:-all}
VITA3KIOS_DEVICE=${VITA3KIOS_DEVICE:-}
VITA3KIOS_TEAM=${VITA3KIOS_DEVELOPMENT_TEAM:-}
VITA3KIOS_PRODUCT_ID=${VITA3KIOS_PRODUCT_BUNDLE_IDENTIFIER:-org.vita3kios.app}
VITA3KIOS_PROBE_PREFIX=${VITA3KIOS_PROBE_BUNDLE_PREFIX:-org.vita3kios.probes}
VITA3KIOS_JIT_ID="$VITA3KIOS_PROBE_PREFIX.jit"
VITA3KIOS_MOLTENVK_ID="$VITA3KIOS_PROBE_PREFIX.moltenvk"
VITA3KIOS_EVIDENCE_ROOT=${VITA3KIOS_EVIDENCE_ROOT:-$VITA3KIOS_ROOT/Build/DeviceEvidence}
VITA3KIOS_RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
VITA3KIOS_EVIDENCE_DIR="$VITA3KIOS_EVIDENCE_ROOT/$VITA3KIOS_RUN_ID"
VITA3KIOS_SIGNED_PROBE_ROOT=${VITA3KIOS_SIGNED_BUILD_ROOT:-${TMPDIR:-/tmp}/vita3kios-device-probes}
VITA3KIOS_SIGNED_PRODUCT_ROOT=${VITA3KIOS_SIGNED_PRODUCT_BUILD_ROOT:-${TMPDIR:-/tmp}/vita3kios-product}
VITA3KIOS_JIT_APP="${VITA3KIOS_SIGNED_PROBE_ROOT%/}/JIT/Release-iphoneos/vita3kios JIT Probe.app"
VITA3KIOS_MOLTENVK_APP="${VITA3KIOS_SIGNED_PROBE_ROOT%/}/MoltenVK/Release-iphoneos/vita3kios MoltenVK Probe.app"
VITA3KIOS_PRODUCT_APP="${VITA3KIOS_SIGNED_PRODUCT_ROOT%/}/device/Release-iphoneos/vita3kios.app"

case "$VITA3KIOS_ACTION" in
    build|m1|collect-m1|m2|m3|all) ;;
    *)
        echo "usage: $0 [build|m1|collect-m1|m2|m3|all]" >&2
        exit 64
        ;;
esac

if [ -z "$VITA3KIOS_TEAM" ]; then
    echo "error: VITA3KIOS_DEVELOPMENT_TEAM is required" >&2
    exit 1
fi
if [ "$VITA3KIOS_ACTION" != "build" ] && [ -z "$VITA3KIOS_DEVICE" ]; then
    echo "error: VITA3KIOS_DEVICE is required for device actions" >&2
    exit 1
fi

build_all() {
    VITA3KIOS_SIGNING=YES \
    VITA3KIOS_DEVELOPMENT_TEAM="$VITA3KIOS_TEAM" \
    VITA3KIOS_PROBE_BUNDLE_PREFIX="$VITA3KIOS_PROBE_PREFIX" \
    VITA3KIOS_SIGNED_BUILD_ROOT="$VITA3KIOS_SIGNED_PROBE_ROOT" \
        "$VITA3KIOS_SCRIPT_DIR/build-device-probes.sh" all

    VITA3KIOS_SIGNING=YES \
    VITA3KIOS_DEVELOPMENT_TEAM="$VITA3KIOS_TEAM" \
    VITA3KIOS_PRODUCT_BUNDLE_IDENTIFIER="$VITA3KIOS_PRODUCT_ID" \
    VITA3KIOS_SIGNED_BUILD_ROOT="$VITA3KIOS_SIGNED_PRODUCT_ROOT" \
        "$VITA3KIOS_SCRIPT_DIR/build-app.sh" device

    "$VITA3KIOS_SCRIPT_DIR/inspect-device-probe.sh" --require-signed "$VITA3KIOS_JIT_APP"
    "$VITA3KIOS_SCRIPT_DIR/inspect-device-probe.sh" --require-signed "$VITA3KIOS_MOLTENVK_APP"
    "$VITA3KIOS_SCRIPT_DIR/inspect-device-probe.sh" --require-signed "$VITA3KIOS_PRODUCT_APP"
    echo "signed_device_artifacts=passed"
}

require_artifact() {
    if [ ! -d "$1" ]; then
        echo "error: signed artifact is missing; run '$0 build' first: $1" >&2
        exit 1
    fi
}

uninstall_project_apps() {
    # A free development profile permits only a small number of installed apps.
    # Device-gate actions therefore rotate only this project's three bundles.
    xcrun devicectl device uninstall app --device "$VITA3KIOS_DEVICE" --timeout 20 \
        "$VITA3KIOS_JIT_ID" >/dev/null 2>&1 || true
    xcrun devicectl device uninstall app --device "$VITA3KIOS_DEVICE" --timeout 20 \
        "$VITA3KIOS_MOLTENVK_ID" >/dev/null 2>&1 || true
    xcrun devicectl device uninstall app --device "$VITA3KIOS_DEVICE" --timeout 20 \
        "$VITA3KIOS_PRODUCT_ID" >/dev/null 2>&1 || true
}

install_and_launch() {
    VITA3KIOS_APP=$1
    VITA3KIOS_BUNDLE_ID=$2
    uninstall_project_apps
    xcrun devicectl device install app --device "$VITA3KIOS_DEVICE" --timeout 60 \
        "$VITA3KIOS_APP"
    xcrun devicectl device process launch --device "$VITA3KIOS_DEVICE" --timeout 30 \
        --terminate-existing "$VITA3KIOS_BUNDLE_ID"
}

record_device() {
    mkdir -p "$VITA3KIOS_EVIDENCE_DIR"
    xcrun devicectl device info details --device "$VITA3KIOS_DEVICE" --show detailed \
        --timeout 30 --json-output "$VITA3KIOS_EVIDENCE_DIR/device.json" >/dev/null
}

copy_report() {
    VITA3KIOS_BUNDLE_ID=$1
    VITA3KIOS_SOURCE=$2
    VITA3KIOS_DESTINATION=$3
    mkdir -p "$(dirname -- "$VITA3KIOS_DESTINATION")"
    xcrun devicectl device copy from --device "$VITA3KIOS_DEVICE" --timeout 30 \
        --domain-type appDataContainer --domain-identifier "$VITA3KIOS_BUNDLE_ID" \
        --source "$VITA3KIOS_SOURCE" --destination "$VITA3KIOS_DESTINATION"
}

require_json_value() {
    VITA3KIOS_REPORT=$1
    VITA3KIOS_KEY=$2
    VITA3KIOS_EXPECTED=$3
    VITA3KIOS_ACTUAL=$(plutil -extract "$VITA3KIOS_KEY" raw "$VITA3KIOS_REPORT")
    if [ "$VITA3KIOS_ACTUAL" != "$VITA3KIOS_EXPECTED" ]; then
        echo "error: $VITA3KIOS_KEY expected '$VITA3KIOS_EXPECTED', got '$VITA3KIOS_ACTUAL'" >&2
        exit 1
    fi
}

collect_m1() {
    VITA3KIOS_REPORT="$VITA3KIOS_EVIDENCE_DIR/m1/latest-report.json"
    record_device
    copy_report "$VITA3KIOS_JIT_ID" Documents/latest-report.json "$VITA3KIOS_REPORT"
    require_json_value "$VITA3KIOS_REPORT" passed true
    require_json_value "$VITA3KIOS_REPORT" required_iterations 20
    require_json_value "$VITA3KIOS_REPORT" completed_iterations 20
    require_json_value "$VITA3KIOS_REPORT" summary.passed_iterations 20
    require_json_value "$VITA3KIOS_REPORT" summary.failed_cases 0
    require_json_value "$VITA3KIOS_REPORT" summary.skipped_cases 0
    echo "M1=passed"
    echo "M1_evidence=$VITA3KIOS_REPORT"
}

run_m1() {
    require_artifact "$VITA3KIOS_JIT_APP"
    record_device
    install_and_launch "$VITA3KIOS_JIT_APP" "$VITA3KIOS_JIT_ID"
    echo "M1_probe=launched"
    echo "Enable JIT with the documented local method, return to the probe, tap Run Probe,"
    echo "then run '$0 collect-m1' with the same environment variables."
}

run_m2() {
    require_artifact "$VITA3KIOS_MOLTENVK_APP"
    record_device
    install_and_launch "$VITA3KIOS_MOLTENVK_APP" "$VITA3KIOS_MOLTENVK_ID"
    sleep 8
    VITA3KIOS_REPORT="$VITA3KIOS_EVIDENCE_DIR/m2/latest-report.json"
    copy_report "$VITA3KIOS_MOLTENVK_ID" Documents/latest-report.json "$VITA3KIOS_REPORT"
    require_json_value "$VITA3KIOS_REPORT" status passed-clear-and-triangle
    require_json_value "$VITA3KIOS_REPORT" presentation.clearFramePresented true
    require_json_value "$VITA3KIOS_REPORT" presentation.triangleFramePresented true
    echo "M2=passed"
    echo "M2_evidence=$VITA3KIOS_REPORT"
}

run_m3() {
    require_artifact "$VITA3KIOS_PRODUCT_APP"
    record_device
    install_and_launch "$VITA3KIOS_PRODUCT_APP" "$VITA3KIOS_PRODUCT_ID"
    sleep 4
    VITA3KIOS_REPORT="$VITA3KIOS_EVIDENCE_DIR/m3/m3-core-report.json"
    copy_report "$VITA3KIOS_PRODUCT_ID" Documents/m3-core-report.json "$VITA3KIOS_REPORT"
    require_json_value "$VITA3KIOS_REPORT" milestone M3
    require_json_value "$VITA3KIOS_REPORT" status passed-core-link-and-query
    require_json_value "$VITA3KIOS_REPORT" allocatorSelfTestPassed true
    require_json_value "$VITA3KIOS_REPORT" platform iphoneos-arm64
    echo "M3=passed"
    echo "M3_evidence=$VITA3KIOS_REPORT"
}

case "$VITA3KIOS_ACTION" in
    build)
        build_all
        ;;
    m1)
        run_m1
        ;;
    collect-m1)
        collect_m1
        ;;
    m2)
        run_m2
        ;;
    m3)
        run_m3
        ;;
    all)
        build_all
        run_m2
        run_m3
        run_m1
        ;;
esac
