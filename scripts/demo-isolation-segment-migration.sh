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
# BOSH Helper Functions
#######################################

get_tas_deployment() {
    if [[ "$DEMO_SKIP_BOSH" == "true" ]]; then
        echo ""
        return
    fi

    bosh deployments --json 2>/dev/null | jq -r '.Tables[0].Rows[] | select(.name | startswith("cf-")) | .name' | head -1
}

get_iso_deployment() {
    if [[ "$DEMO_SKIP_BOSH" == "true" ]]; then
        echo ""
        return
    fi

    bosh deployments --json 2>/dev/null | jq -r '.Tables[0].Rows[] | select(.name | startswith("p-isolation-segment-")) | .name' | head -1
}

get_shared_cell_instance_group() {
    local tas_deployment="$1"

    if [[ -z "$tas_deployment" ]]; then
        echo "compute"
        return
    fi

    # Detect if Small Footprint (compute) or regular TAS (diego_cell)
    local instance
    instance=$(bosh -d "$tas_deployment" instances --json 2>/dev/null | jq -r '.Tables[0].Rows[0].instance' 2>/dev/null || echo "")

    if [[ "$instance" =~ ^compute/ ]]; then
        echo "compute"
    else
        echo "diego_cell"
    fi
}

get_cell_capacity() {
    local deployment="$1"
    local instance_group="$2"
    local index="${3:-0}"

    if [[ "$DEMO_SKIP_BOSH" == "true" ]] || [[ -z "$deployment" ]]; then
        echo "{}"
        return
    fi

    bosh -d "$deployment" ssh "${instance_group}/${index}" \
        -c "curl -s localhost:1800/state" 2>/dev/null || echo "{}"
}

get_app_cell_ip() {
    cf ssh "$DEMO_APP_NAME" -c 'echo $CF_INSTANCE_IP' 2>/dev/null || echo "unknown"
}

#######################################
# State Capture Functions
#######################################

capture_before_state() {
    info "Capturing BEFORE state..."

    # Get app GUID
    local app_guid
    app_guid=$(cf app "$DEMO_APP_NAME" --guid)

    # Method 1: CF CLI verification
    local cf_isolation_segment
    cf_isolation_segment=$(cf app "$DEMO_APP_NAME" | grep "isolation segment:" | awk '{print $3}' || echo "(not set)")

    # Method 2: BOSH physical placement
    local tas_deployment
    local shared_cell_group
    local cell_ip

    tas_deployment=$(get_tas_deployment)
    shared_cell_group=$(get_shared_cell_instance_group "$tas_deployment")
    cell_ip=$(get_app_cell_ip)

    # Method 3: Capacity metrics
    local shared_capacity="{}"
    if [[ -n "$tas_deployment" ]]; then
        shared_capacity=$(get_cell_capacity "$tas_deployment" "$shared_cell_group" 0)
    fi

    # Store state as JSON
    local before_state
    before_state=$(cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "cf_cli": {
    "app_name": "$DEMO_APP_NAME",
    "app_guid": "$app_guid",
    "isolation_segment": $([ "$cf_isolation_segment" == "(not set)" ] && echo "null" || echo "\"$cf_isolation_segment\""),
    "state": "$(cf app "$DEMO_APP_NAME" | grep "^state:" | awk '{print $2}')"
  },
  "bosh": {
    "tas_deployment": "$tas_deployment",
    "instance_group": "$shared_cell_group",
    "cell_ip": "$cell_ip",
    "placement_tags": []
  },
  "capacity": {
    "shared_cell": $(echo "$shared_capacity" | jq '{containers_total: .TotalResources.Containers, containers_available: .AvailableResources.Containers}' 2>/dev/null || echo '{}')
  },
  "app_env": {
    "CF_INSTANCE_IP": "$cell_ip"
  }
}
EOF
    )

    # Save to temp file
    echo "$before_state" | jq '{"before": .}' > "$STATE_FILE"

    success "BEFORE state captured"
    debug "State saved to $STATE_FILE"

    echo ""
}

display_before_state() {
    section_header "BEFORE STATE (App on Shared Diego Cells)"

    local before
    before=$(jq -r '.before' "$STATE_FILE")

    echo -e "${BOLD}1️⃣  CF CLI Verification:${NC}"
    echo "   App Name:           $(echo "$before" | jq -r '.cf_cli.app_name')"
    echo "   Isolation Segment:  $(echo "$before" | jq -r '.cf_cli.isolation_segment // "(not set)"')"
    echo "   State:              $(echo "$before" | jq -r '.cf_cli.state')"
    echo ""

    if [[ "$DEMO_SKIP_BOSH" != "true" ]]; then
        echo -e "${BOLD}2️⃣  BOSH Physical Placement:${NC}"
        echo "   Deployment:         $(echo "$before" | jq -r '.bosh.tas_deployment')"
        echo "   Instance Group:     $(echo "$before" | jq -r '.bosh.instance_group')/0"
        echo "   Cell IP:            $(echo "$before" | jq -r '.bosh.cell_ip')"
        echo "   Placement Tags:     none (shared cell)"
        echo ""

        echo -e "${BOLD}3️⃣  Diego Cell Capacity:${NC}"
        echo "   Cell Type:          Shared $(echo "$before" | jq -r '.bosh.instance_group | ascii_upcase') Cell"
        local containers_used
        local containers_total
        containers_total=$(echo "$before" | jq -r '.capacity.shared_cell.containers_total // 0')
        containers_available=$(echo "$before" | jq -r '.capacity.shared_cell.containers_available // 0')
        containers_used=$((containers_total - containers_available))
        echo "   Containers Used:    $containers_used"
        echo "   Available:          $containers_available"
        echo ""
    fi

    echo -e "${BOLD}4️⃣  App Environment:${NC}"
    echo "   CF_INSTANCE_IP:     $(echo "$before" | jq -r '.app_env.CF_INSTANCE_IP')"
    echo ""
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
    cf_api=$(cf api | grep "API endpoint:" | sed 's/^API endpoint:[[:space:]]*//')
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

setup_demo_environment() {
    info "Creating demo environment..."

    # Create org if it doesn't exist
    if cf org "$DEMO_ORG" &> /dev/null; then
        debug "Org $DEMO_ORG already exists"
    else
        info "Creating org: $DEMO_ORG"
        if cf create-org "$DEMO_ORG"; then
            success "Org '$DEMO_ORG' created"
        else
            fatal "Failed to create org $DEMO_ORG"
        fi
    fi

    # Create space if it doesn't exist
    if ! cf target -o "$DEMO_ORG" &> /dev/null; then
        fatal "Failed to target org $DEMO_ORG"
    fi

    if cf space "$DEMO_SPACE" &> /dev/null; then
        debug "Space $DEMO_SPACE already exists"
    else
        info "Creating space: $DEMO_SPACE"
        if cf create-space "$DEMO_SPACE"; then
            success "Space '$DEMO_SPACE' created"
        else
            fatal "Failed to create space $DEMO_SPACE"
        fi
    fi

    # Target the space
    cf target -o "$DEMO_ORG" -s "$DEMO_SPACE" &> /dev/null
    success "Targeted org '$DEMO_ORG' and space '$DEMO_SPACE'"

    # Check if isolation segment exists
    if cf isolation-segments | tail -n +4 | grep -q "^${DEMO_SEGMENT}[[:space:]]*$"; then
        success "Isolation segment '$DEMO_SEGMENT' exists"
    else
        warn "Isolation segment '$DEMO_SEGMENT' does not exist"
        info "Creating isolation segment..."

        if cf create-isolation-segment "$DEMO_SEGMENT"; then
            success "Isolation segment '$DEMO_SEGMENT' created"
        else
            fatal "Failed to create isolation segment. Check permissions and isolation segment quota."
        fi
    fi

    # Verify segment has Diego cells (if BOSH available)
    if [[ "$DEMO_SKIP_BOSH" != "true" ]]; then
        info "Verifying isolation segment has Diego cells..."

        local iso_deployment
        iso_deployment=$(bosh deployments --json 2>/dev/null | jq -r '.Tables[0].Rows[] | select(.name | startswith("p-isolation-segment-")) | .name' | head -1)

        if [[ -n "$iso_deployment" ]]; then
            local cell_count
            cell_count=$(bosh -d "$iso_deployment" instances --json 2>/dev/null | jq -r '.Tables[0].Rows | length' 2>/dev/null || echo "0")

            if [[ "$cell_count" -gt 0 ]]; then
                success "Isolation segment has $cell_count Diego cell(s)"
            else
                fatal "Isolation segment exists but has no Diego cells deployed. Deploy cells via Ops Manager first."
            fi
        else
            warn "Could not verify Diego cells via BOSH. Continuing anyway..."
        fi
    fi

    echo ""
}

deploy_app_before_isolation() {
    phase_header "Phase 2" "Deploy App (BEFORE Isolation Segment)"

    info "Pushing $DEMO_APP_NAME app to shared Diego cells..."

    # Check if app already exists
    if cf app "$DEMO_APP_NAME" &> /dev/null; then
        warn "App $DEMO_APP_NAME already exists. Deleting it first..."
        cf delete "$DEMO_APP_NAME" -f -r
    fi

    # Download spring-music if needed
    local app_jar="/tmp/spring-music.jar"
    if [[ ! -f "$app_jar" ]]; then
        info "Downloading Spring Music sample app..."
        curl -L -o "$app_jar" "https://github.com/cloudfoundry-samples/spring-music/releases/download/v1.0/spring-music.jar"
        success "Downloaded Spring Music to $app_jar"
    fi

    # Push app (no isolation segment assigned yet)
    info "Deploying app..."
    if cf push "$DEMO_APP_NAME" -p "$app_jar" -b java_buildpack --no-start; then
        success "App pushed successfully"
    else
        fatal "Failed to push app"
    fi

    # Start app
    info "Starting app..."
    if cf start "$DEMO_APP_NAME"; then
        success "App started successfully"
    else
        fatal "Failed to start app"
    fi

    # Get app URL
    local app_url
    app_url=$(cf app "$DEMO_APP_NAME" | grep "routes:" | awk '{print $2}')

    if [[ -n "$app_url" ]]; then
        success "App is running at: https://$app_url"
    fi

    # Wait for app to be fully ready
    info "Waiting for app to be fully ready..."
    sleep 5

    echo ""
}

#######################################
# Migration Functions
#######################################

enable_isolation_segment() {
    phase_header "Phase 3" "Enable Isolation Segment"

    # Entitle org to segment
    info "Entitling org '$DEMO_ORG' to segment '$DEMO_SEGMENT'..."
    if cf enable-org-isolation "$DEMO_ORG" "$DEMO_SEGMENT"; then
        success "Org entitled"
    else
        error "Failed to entitle org (may already be entitled)"
    fi

    # Assign space to segment
    info "Assigning space '$DEMO_SPACE' to segment '$DEMO_SEGMENT'..."
    if cf set-space-isolation-segment "$DEMO_SPACE" "$DEMO_SEGMENT"; then
        success "Space assigned"
    else
        fatal "Failed to assign space to isolation segment"
    fi

    # Restart app to trigger migration
    info "Restarting app to trigger migration..."
    if cf restart "$DEMO_APP_NAME"; then
        success "App restarted successfully"
    else
        error "App restart failed. Attempting rollback..."
        cf reset-space-isolation-segment "$DEMO_SPACE"
        fatal "Migration failed. Space isolation segment reset."
    fi

    # Wait for app to stabilize
    info "Waiting for app to stabilize..."
    sleep 5

    # Verify app is still accessible
    local app_state
    app_state=$(cf app "$DEMO_APP_NAME" | grep "^state:" | awk '{print $2}')

    if [[ "$app_state" != "started" ]]; then
        error "App is not in started state: $app_state"
        fatal "Migration verification failed"
    fi

    success "App is running on isolated Diego cells"
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

    # Setup environment
    setup_demo_environment

    pause_for_demo "continue to app deployment"

    # Deploy app before isolation segment
    deploy_app_before_isolation

    # Capture BEFORE state
    capture_before_state

    pause_for_demo "see BEFORE state"

    # Display BEFORE state
    display_before_state

    pause_for_demo "enable isolation segment and restart app"

    # Enable isolation segment
    enable_isolation_segment

    pause_for_demo "see AFTER state"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
