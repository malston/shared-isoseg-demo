#!/usr/bin/env bash
# ABOUTME: Pre-flight checklist script for demo recording
# ABOUTME: Validates environment, credentials, and pre-deployed apps

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASS=0
FAIL=0
WARN=0

#######################################
# Check Functions
#######################################

check_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    ((PASS++)) || true
}

check_fail() {
    echo -e "  ${RED}✗${NC} $1"
    ((FAIL++)) || true
}

check_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    ((WARN++)) || true
}

check_info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

section() {
    echo ""
    echo -e "${BLUE}━━━ $1 ━━━${NC}"
}

#######################################
# Environment Checks
#######################################

check_cli_tools() {
    section "CLI Tools"

    # Required tools
    for cmd in cf om pivnet jq bosh; do
        if command -v "$cmd" &> /dev/null; then
            local version=""
            case "$cmd" in
                cf)    version=$(cf version 2>/dev/null | head -1 || echo "unknown") ;;
                om)    version=$(om version 2>/dev/null || echo "unknown") ;;
                pivnet) version=$(pivnet --version 2>/dev/null || echo "unknown") ;;
                jq)    version=$(jq --version 2>/dev/null || echo "unknown") ;;
                bosh)  version=$(bosh --version 2>/dev/null | head -1 || echo "unknown") ;;
            esac
            check_pass "$cmd: ${version:-available}"
        else
            check_fail "$cmd: not found"
        fi
    done

    # Optional but helpful
    for cmd in gh watch; do
        if command -v "$cmd" &> /dev/null; then
            check_pass "$cmd: available"
        else
            check_warn "$cmd: not found (optional)"
        fi
    done
}

check_environment_variables() {
    section "Environment Variables"

    # Ops Manager
    if [[ -n "${OM_TARGET:-}" ]]; then
        check_pass "OM_TARGET: ${OM_TARGET}"
    else
        check_fail "OM_TARGET: not set"
    fi

    if [[ -n "${OM_USERNAME:-}" ]]; then
        check_pass "OM_USERNAME: ${OM_USERNAME}"
    else
        check_fail "OM_USERNAME: not set"
    fi

    if [[ -n "${OM_PASSWORD:-}" ]]; then
        check_pass "OM_PASSWORD: (set, hidden)"
    else
        check_fail "OM_PASSWORD: not set"
    fi

    # Pivnet
    if [[ -n "${PIVNET_TOKEN:-}" ]]; then
        check_pass "PIVNET_TOKEN: (set, hidden)"
    else
        check_warn "PIVNET_TOKEN: not set (needed for tile download)"
    fi

    # CF credentials (optional if already logged in)
    if [[ -n "${CF_USERNAME:-}" ]]; then
        check_pass "CF_USERNAME: ${CF_USERNAME}"
    else
        check_info "CF_USERNAME: not set (using cf login session)"
    fi
}

check_ops_manager_connection() {
    section "Ops Manager Connection"

    if [[ -z "${OM_TARGET:-}" ]]; then
        check_fail "Cannot test - OM_TARGET not set"
        return
    fi

    if om curl --path /api/v0/info &> /dev/null; then
        check_pass "Ops Manager API accessible"

        # Get staged products
        local products
        products=$(om staged-products --format json 2>/dev/null | jq -r '.[].name' | tr '\n' ', ' | sed 's/,$//')
        check_info "Staged products: $products"
    else
        check_fail "Cannot connect to Ops Manager at ${OM_TARGET}"
    fi
}

check_cf_connection() {
    section "Cloud Foundry Connection"

    if cf target &> /dev/null; then
        local api org space target_output
        target_output=$(cf target 2>/dev/null || echo "")
        api=$(echo "$target_output" | grep -i "api endpoint" | awk '{print $NF}' || echo "unknown")
        org=$(echo "$target_output" | grep -i "^org:" | awk '{print $2}' || echo "unknown")
        space=$(echo "$target_output" | grep -i "^space:" | awk '{print $2}' || echo "unknown")

        check_pass "CF API: ${api:-unknown}"
        check_pass "Org: ${org:-not targeted}"
        check_pass "Space: ${space:-not targeted}"
    else
        check_fail "Not logged into Cloud Foundry"
        check_info "Run: cf login -a <API_URL>"
    fi
}

check_demo_prerequisites() {
    section "Demo Prerequisites"

    # Check demo org exists
    if cf org demo-org &> /dev/null; then
        check_pass "Org 'demo-org' exists"
    else
        check_fail "Org 'demo-org' not found"
        check_info "Create with: cf create-org demo-org"
    fi

    # Check spaces exist (need to target org first)
    # Target demo-org to check spaces
    if cf target -o demo-org &> /dev/null 2>&1; then
        for space in dev-space iso-validation; do
            if cf space "$space" &> /dev/null 2>&1; then
                check_pass "Space '$space' exists in demo-org"
            else
                check_fail "Space '$space' not found in demo-org"
                check_info "Create with: cf create-space $space -o demo-org"
            fi
        done
    else
        check_warn "Could not target demo-org to check spaces"
    fi

    # Check Spring Music is deployed
    if cf target -o demo-org -s dev-space &> /dev/null 2>&1; then
        if cf app spring-music &> /dev/null 2>&1; then
            local state=""
            state=$(cf app spring-music 2>/dev/null | grep -i "^requested state:" | awk '{print $3}') || state="unknown"
            if [[ "$state" == "started" ]]; then
                check_pass "Spring Music app running in dev-space"
            else
                check_warn "Spring Music app exists but state is: ${state:-unknown}"
            fi
        else
            check_fail "Spring Music app not found in dev-space"
            check_info "Deploy with: cf push spring-music (from spring-music directory)"
        fi
    else
        check_warn "Could not target demo-org/dev-space to check Spring Music"
    fi

    # Check cf-env app is built
    local cfenv_path
    cfenv_path="$(dirname "${BASH_SOURCE[0]}")/../apps/cf-env"
    if [[ -f "$cfenv_path/cf-env" ]] || [[ -f "$cfenv_path/main.go" ]]; then
        check_pass "cf-env app source available"
    else
        check_warn "cf-env app not found at $cfenv_path"
    fi
}

check_tile_files() {
    section "Tile Files (Optional - can download during demo)"

    local download_dir="${HOME}/Downloads"

    # Check for isolation segment tile
    local tile=""
    tile=$(find "$download_dir" -maxdepth 1 -name "p-isolation-segment-*.pivotal" -type f 2>/dev/null | head -1) || true
    if [[ -n "$tile" ]]; then
        check_pass "Isolation segment tile: $(basename "$tile")"
    else
        check_info "No isolation segment tile in $download_dir"
        check_info "Download with: ./scripts/isolation-segment-tile-migration.sh download-tile --version 6.0"
    fi

    # Check for replicator
    if [[ -x "$download_dir/replicator" ]] || [[ -x "./replicator" ]] || [[ -x "/tmp/replicator" ]]; then
        check_pass "Replicator tool available"
    else
        check_info "Replicator not found"
        check_info "Download with: ./scripts/isolation-segment-tile-migration.sh download-replicator --version <release>"
    fi
}

check_terminal_settings() {
    section "Terminal Settings"

    # Check terminal size
    local cols lines
    cols=$(tput cols)
    lines=$(tput lines)

    if [[ $cols -ge 120 ]]; then
        check_pass "Terminal width: ${cols} columns (good for recording)"
    else
        check_warn "Terminal width: ${cols} columns (recommend 120+)"
    fi

    if [[ $lines -ge 30 ]]; then
        check_pass "Terminal height: ${lines} lines"
    else
        check_warn "Terminal height: ${lines} lines (recommend 30+)"
    fi

    # Check if running in iTerm2
    if [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]]; then
        check_pass "Running in iTerm2"
    elif [[ "${TERM_PROGRAM:-}" == "Apple_Terminal" ]]; then
        check_pass "Running in Terminal.app"
    else
        check_info "Terminal: ${TERM_PROGRAM:-unknown}"
    fi
}

check_recording_tools() {
    section "Recording Tools (Optional)"

    # Check for common recording tools
    if [[ -d "/Applications/OBS.app" ]]; then
        check_pass "OBS Studio installed"
    else
        check_info "OBS Studio not found (recommended for multi-source recording)"
    fi

    if [[ -d "/Applications/ScreenFlow.app" ]]; then
        check_pass "ScreenFlow installed"
    else
        check_info "ScreenFlow not found"
    fi

    # QuickTime is always available on macOS
    if [[ -d "/System/Applications/QuickTime Player.app" ]]; then
        check_pass "QuickTime Player available"
    fi
}

#######################################
# Summary
#######################################

print_summary() {
    echo ""
    echo -e "${BLUE}━━━ Summary ━━━${NC}"
    echo ""
    echo -e "  ${GREEN}Passed:${NC}   $PASS"
    echo -e "  ${YELLOW}Warnings:${NC} $WARN"
    echo -e "  ${RED}Failed:${NC}   $FAIL"
    echo ""

    if [[ $FAIL -eq 0 ]]; then
        echo -e "${GREEN}✓ Ready for recording!${NC}"
        echo ""
        echo "Quick tips before you start:"
        echo "  1. Increase terminal font size (Cmd+Plus in iTerm2)"
        echo "  2. Set a simple prompt: export PS1='\$ '"
        echo "  3. Clear terminal history: clear && history -c"
        echo "  4. Have the runbook open: docs/demo-recording-runbook.md"
    else
        echo -e "${RED}✗ Please fix the failed checks before recording${NC}"
    fi
    echo ""
}

#######################################
# Main
#######################################

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Demo Recording Pre-Flight Checklist      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"

    check_cli_tools
    check_environment_variables
    check_ops_manager_connection
    check_cf_connection
    check_demo_prerequisites
    check_tile_files
    check_terminal_settings
    check_recording_tools

    print_summary

    # Exit with appropriate code
    if [[ $FAIL -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
