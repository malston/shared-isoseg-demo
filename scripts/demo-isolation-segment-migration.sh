#!/usr/bin/env bash
# ABOUTME: Interactive demo script showing zero-impact migration from shared to isolated Diego cells
# ABOUTME: Supports both presentation mode (with pauses) and automated mode (CI/testing)

set -euo pipefail

# Script version
VERSION="1.0.0"

# Default configuration
: "${DEMO_MODE:=interactive}"
: "${DEMO_SEGMENT:=shared-demo}"
: "${DEMO_ORG:=shared-isoseg-demo}"
: "${DEMO_SPACE:=dev}"
: "${DEMO_APP_NAME:=spring-music}"
: "${DEMO_CLEANUP:=ask}"
: "${DEMO_SKIP_BOSH:=false}"
: "${VERBOSE:=false}"

# State file for comparison
STATE_FILE="/tmp/demo-state-$(date +%s).json"

# Colors for output
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    BOLD=''
    NC=''
fi

#######################################
# Utility Functions
#######################################

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $*"
}

info() {
    if [[ "$DEMO_MODE" == "interactive" ]]; then
        echo -e "${BLUE}ℹ${NC}  $*"
    else
        log "INFO: $*"
    fi
}

success() {
    if [[ "$DEMO_MODE" == "interactive" ]]; then
        echo -e "${GREEN}✓${NC}  $*"
    else
        log "✓ $*"
    fi
}

warn() {
    if [[ "$DEMO_MODE" == "interactive" ]]; then
        echo -e "${YELLOW}⚠${NC}  $*" >&2
    else
        log "WARNING: $*" >&2
    fi
}

error() {
    if [[ "$DEMO_MODE" == "interactive" ]]; then
        echo -e "${RED}✗${NC}  $*" >&2
    else
        log "ERROR: $*" >&2
    fi
}

fatal() {
    error "$@"
    exit 1
}

debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        log "DEBUG: $@"
    fi
}

pause_for_demo() {
    if [[ "$DEMO_MODE" == "interactive" ]]; then
        echo ""
        echo -e "${CYAN}[Press Enter to $1]${NC}"
        read -r
    fi
}

section_header() {
    local title="$1"
    echo ""
    if [[ "$DEMO_MODE" == "interactive" ]]; then
        echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
        printf "${BOLD}║ %-62s ║${NC}\n" "$title"
        echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    else
        log "=== $title ==="
    fi
    echo ""
}

phase_header() {
    local phase="$1"
    local title="$2"
    echo ""
    if [[ "$DEMO_MODE" == "interactive" ]]; then
        echo -e "${BOLD}${MAGENTA}$phase: $title${NC}"
        echo "------------------------------"
    else
        log "$phase: $title"
    fi
}

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        fatal "Required command '$cmd' not found. Please install it and try again."
    fi
}

#######################################
# Prerequisite Validation
#######################################

validate_prerequisites() {
    phase_header "Phase 1" "Prerequisites & Setup"

    # Check required commands
    require_command cf
    require_command jq
    require_command curl

    if [[ "$DEMO_SKIP_BOSH" != "true" ]]; then
        require_command bosh
    fi

    success "CF CLI found ($(cf version | head -1))"
    success "jq found ($(jq --version))"

    if [[ "$DEMO_SKIP_BOSH" != "true" ]]; then
        success "BOSH CLI found ($(bosh --version | head -1))"
    fi

    # Validate CF connection
    info "Validating Cloud Foundry connection..."
    if ! cf api &> /dev/null; then
        fatal "Not connected to Cloud Foundry. Run 'cf login' first."
    fi

    if ! cf target &> /dev/null; then
        fatal "Not authenticated to Cloud Foundry. Run 'cf login' first."
    fi

    local cf_api
    cf_api=$(cf api | grep "API endpoint:" | awk '{print $3}')
    success "Connected to CF API: $cf_api"

    # Validate BOSH connection if not skipped
    if [[ "$DEMO_SKIP_BOSH" != "true" ]]; then
        info "Validating BOSH connection..."

        if ! bosh env &> /dev/null; then
            warn "Cannot connect to BOSH Director. BOSH verification will be limited."
            warn "Set DEMO_SKIP_BOSH=true to skip BOSH verification entirely."
            DEMO_SKIP_BOSH="true"
        else
            local bosh_env
            bosh_env=$(bosh env --json | jq -r '.Tables[0].Rows[0].name' 2>/dev/null || echo "unknown")
            success "Connected to BOSH: $bosh_env"
        fi
    fi

    echo ""
}

#######################################
# Main
#######################################

main() {
    # Show banner
    if [[ "$DEMO_MODE" == "interactive" ]]; then
        section_header "Isolation Segment Migration Demo"
    else
        log "Starting isolation segment migration demo"
    fi

    # Validate prerequisites
    validate_prerequisites

    info "Demo configuration:"
    info "  Mode: $DEMO_MODE"
    info "  Org: $DEMO_ORG"
    info "  Space: $DEMO_SPACE"
    info "  Segment: $DEMO_SEGMENT"
    info "  App: $DEMO_APP_NAME"
    info "  BOSH verification: $([ "$DEMO_SKIP_BOSH" == "true" ] && echo "disabled" || echo "enabled")"
    echo ""
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
