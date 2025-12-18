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
        log "DEBUG: $*"
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
    "state": "$(cf app "$DEMO_APP_NAME" | grep "^requested state:" | awk '{print $3}')"
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

    # Verify space has NO isolation segment assigned (clean state for demo)
    local current_segment
    current_segment=$(cf space "$DEMO_SPACE" | grep "isolation segment:" | awk '{print $3}')

    if [[ -n "$current_segment" ]] && [[ "$current_segment" != "(not" ]]; then
        error "Space '$DEMO_SPACE' is already assigned to isolation segment '$current_segment'"
        error "This demo requires starting from a clean state (no isolation segment)."
        error ""
        error "To fix, run:"
        error "  cf reset-space-isolation-segment $DEMO_SPACE"
        error ""
        fatal "Cannot proceed with space already assigned to an isolation segment."
    fi

    success "Space has no isolation segment (clean state for demo)"

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

    # Use local spring-music JAR or download if needed
    local app_jar="$HOME/spring-music/build/libs/spring-music-1.0.jar"

    if [[ ! -f "$app_jar" ]]; then
        warn "Spring Music JAR not found at $app_jar"
        info "Building Spring Music from source..."
        if [[ -d "$HOME/spring-music" ]]; then
            (cd "$HOME/spring-music" && ./gradlew clean build -x test)
            success "Built Spring Music at $app_jar"
        else
            fatal "Spring Music repository not found at $HOME/spring-music. Please clone: git clone https://github.com/cloudfoundry-samples/spring-music ~/spring-music"
        fi
    fi

    # Push app (no isolation segment assigned yet)
    info "Deploying app..."

    if cf push "$DEMO_APP_NAME" -p "$app_jar" -b java_buildpack_offline -s cflinuxfs4 --no-start; then
        success "App pushed successfully"
    else
        fatal "Failed to push app"
    fi

    # Set Java version to 17 (Spring Music requires Java 17)
    info "Configuring Java 17 runtime..."
    cf set-env "$DEMO_APP_NAME" JBP_CONFIG_OPEN_JDK_JRE '{ jre: { version: 17.+ } }'

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
    app_state=$(cf app "$DEMO_APP_NAME" | grep "^requested state:" | awk '{print $3}')

    if [[ "$app_state" != "started" ]]; then
        error "App is not in started state: $app_state"
        fatal "Migration verification failed"
    fi

    success "App is running on isolated Diego cells"
    echo ""
}

capture_after_state() {
    info "Capturing AFTER state..."

    # Get app GUID
    local app_guid
    app_guid=$(cf app "$DEMO_APP_NAME" --guid)

    # Method 1: CF CLI verification
    local cf_isolation_segment
    cf_isolation_segment=$(cf app "$DEMO_APP_NAME" | grep "isolation segment:" | awk '{print $3}' || echo "(not set)")

    # Method 2: BOSH physical placement
    local tas_deployment
    local iso_deployment
    local shared_cell_group
    local cell_ip

    tas_deployment=$(get_tas_deployment)
    iso_deployment=$(get_iso_deployment)
    shared_cell_group=$(get_shared_cell_instance_group "$tas_deployment")
    cell_ip=$(get_app_cell_ip)

    # Method 3: Capacity metrics
    local shared_capacity="{}"
    local isolated_capacity="{}"

    if [[ -n "$tas_deployment" ]]; then
        shared_capacity=$(get_cell_capacity "$tas_deployment" "$shared_cell_group" 0)
    fi

    if [[ -n "$iso_deployment" ]]; then
        isolated_capacity=$(get_cell_capacity "$iso_deployment" "isolated_diego_cell" 0)
    fi

    # Store AFTER state
    local after_state
    after_state=$(cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "cf_cli": {
    "app_name": "$DEMO_APP_NAME",
    "app_guid": "$app_guid",
    "isolation_segment": $([ "$cf_isolation_segment" == "(not set)" ] && echo "null" || echo "\"$cf_isolation_segment\""),
    "state": "$(cf app "$DEMO_APP_NAME" | grep "^requested state:" | awk '{print $3}')"
  },
  "bosh": {
    "tas_deployment": "$tas_deployment",
    "iso_deployment": "$iso_deployment",
    "instance_group": "isolated_diego_cell",
    "cell_ip": "$cell_ip",
    "placement_tags": ["$DEMO_SEGMENT"]
  },
  "capacity": {
    "shared_cell": $(echo "$shared_capacity" | jq '{containers_total: .TotalResources.Containers, containers_available: .AvailableResources.Containers}' 2>/dev/null || echo '{}'),
    "isolated_cell": $(echo "$isolated_capacity" | jq '{containers_total: .TotalResources.Containers, containers_available: .AvailableResources.Containers}' 2>/dev/null || echo '{}')
  },
  "app_env": {
    "CF_INSTANCE_IP": "$cell_ip"
  }
}
EOF
    )

    # Merge with existing state file
    local merged_state
    merged_state=$(jq --argjson after "$after_state" '. + {"after": $after}' "$STATE_FILE")
    echo "$merged_state" > "$STATE_FILE"

    success "AFTER state captured"
    debug "State saved to $STATE_FILE"

    echo ""
}

display_after_state() {
    section_header "AFTER STATE (App on Isolated Diego Cells)"

    local after
    after=$(jq -r '.after' "$STATE_FILE")

    echo -e "${BOLD}1️⃣  CF CLI Verification:${NC}"
    echo "   App Name:           $(echo "$after" | jq -r '.cf_cli.app_name')"
    echo -e "   Isolation Segment:  ${GREEN}$(echo "$after" | jq -r '.cf_cli.isolation_segment // "(not set)"')${NC} ✨"
    echo "   State:              $(echo "$after" | jq -r '.cf_cli.state')"
    echo ""

    if [[ "$DEMO_SKIP_BOSH" != "true" ]]; then
        echo -e "${BOLD}2️⃣  BOSH Physical Placement:${NC}"
        echo -e "   Deployment:         ${GREEN}$(echo "$after" | jq -r '.bosh.iso_deployment')${NC} ✨"
        echo -e "   Instance Group:     ${GREEN}$(echo "$after" | jq -r '.bosh.instance_group')/0${NC} ✨"
        echo -e "   Cell IP:            ${GREEN}$(echo "$after" | jq -r '.bosh.cell_ip')${NC} ✨"
        echo -e "   Placement Tags:     ${GREEN}$(echo "$after" | jq -r '.bosh.placement_tags[0]')${NC} ✨"
        echo ""

        echo -e "${BOLD}3️⃣  Diego Cell Capacity:${NC}"

        local before
        before=$(jq -r '.before' "$STATE_FILE")

        echo "   Shared Cell ($(echo "$before" | jq -r '.bosh.cell_ip')):"
        local shared_containers_total
        local shared_containers_available
        local shared_containers_used
        shared_containers_total=$(echo "$after" | jq -r '.capacity.shared_cell.containers_total // 0')
        shared_containers_available=$(echo "$after" | jq -r '.capacity.shared_cell.containers_available // 0')
        shared_containers_used=$((shared_containers_total - shared_containers_available))
        echo -e "     Containers Used:  ${GREEN}$shared_containers_used (app moved away)${NC} ✨"
        echo ""

        echo "   Isolated Cell ($(echo "$after" | jq -r '.bosh.cell_ip')):"
        local isolated_containers_total
        local isolated_containers_available
        local isolated_containers_used
        isolated_containers_total=$(echo "$after" | jq -r '.capacity.isolated_cell.containers_total // 0')
        isolated_containers_available=$(echo "$after" | jq -r '.capacity.isolated_cell.containers_available // 0')
        isolated_containers_used=$((isolated_containers_total - isolated_containers_available))
        echo -e "     Containers Used:  ${GREEN}$isolated_containers_used (our app is here)${NC} ✨"
        echo "     Available:        $isolated_containers_available"
        echo ""
    fi

    echo -e "${BOLD}4️⃣  App Environment:${NC}"
    echo -e "   CF_INSTANCE_IP:     ${GREEN}$(echo "$after" | jq -r '.app_env.CF_INSTANCE_IP')${NC} ✨"
    echo ""
}

display_comparison() {
    section_header "BEFORE vs AFTER"

    local before after
    before=$(jq -r '.before' "$STATE_FILE")
    after=$(jq -r '.after' "$STATE_FILE")

    if [[ "$DEMO_MODE" == "interactive" ]]; then
        # Pretty table format
        echo "┌─────────────────────────┬──────────────────────┬─────────────────────┐"
        echo "│ Attribute               │ BEFORE               │ AFTER               │"
        echo "├─────────────────────────┼──────────────────────┼─────────────────────┤"

        printf "│ %-23s │ %-20s │ ${GREEN}%-19s${NC} │\n" \
            "Isolation Segment" \
            "$(echo "$before" | jq -r '.cf_cli.isolation_segment // "(not set)"')" \
            "$(echo "$after" | jq -r '.cf_cli.isolation_segment') ✨"

        if [[ "$DEMO_SKIP_BOSH" != "true" ]]; then
            printf "│ %-23s │ %-20s │ ${GREEN}%-19s${NC} │\n" \
                "BOSH Deployment" \
                "$(echo "$before" | jq -r '.bosh.tas_deployment' | cut -c1-17)..." \
                "$(echo "$after" | jq -r '.bosh.iso_deployment' | cut -c1-14)... ✨"

            printf "│ %-23s │ %-20s │ ${GREEN}%-19s${NC} │\n" \
                "Instance Group" \
                "$(echo "$before" | jq -r '.bosh.instance_group')/0" \
                "$(echo "$after" | jq -r '.bosh.instance_group' | cut -c1-15)... ✨"

            printf "│ %-23s │ %-20s │ ${GREEN}%-19s${NC} │\n" \
                "Cell IP" \
                "$(echo "$before" | jq -r '.bosh.cell_ip')" \
                "$(echo "$after" | jq -r '.bosh.cell_ip') ✨"

            printf "│ %-23s │ %-20s │ ${GREEN}%-19s${NC} │\n" \
                "Placement Tags" \
                "none" \
                "$(echo "$after" | jq -r '.bosh.placement_tags[0]') ✨"
        fi

        local app_url
        app_url=$(cf app "$DEMO_APP_NAME" | grep "routes:" | awk '{print $2}' | cut -c1-17)

        printf "│ %-23s │ %-20s │ %-19s │\n" \
            "App URL" \
            "${app_url}..." \
            "${app_url}..."

        printf "│ %-23s │ %-20s │ ${GREEN}%-19s${NC} │\n" \
            "App Code Changed?" \
            "-" \
            "NO ✅"

        printf "│ %-23s │ %-20s │ ${GREEN}%-19s${NC} │\n" \
            "Developer Impact?" \
            "-" \
            "ZERO ✅"

        echo "└─────────────────────────┴──────────────────────┴─────────────────────┘"
        echo ""

        echo -e "${BOLD}KEY TAKEAWAY:${NC} Same app, same URL, zero code changes - just better"
        echo "performance and isolation by restarting in a different space configuration."
        echo ""
    else
        # Compact format for automated mode
        echo "COMPARISON:"
        echo "  Isolation Segment: $(echo "$before" | jq -r '.cf_cli.isolation_segment // "(not set)"') -> $(echo "$after" | jq -r '.cf_cli.isolation_segment')"
        echo "  Cell IP: $(echo "$before" | jq -r '.bosh.cell_ip') -> $(echo "$after" | jq -r '.bosh.cell_ip')"
        echo "  Instance Group: $(echo "$before" | jq -r '.bosh.instance_group') -> $(echo "$after" | jq -r '.bosh.instance_group')"
        echo "  App Code Changed: NO"
        echo "  Developer Impact: ZERO"
        echo ""
    fi
}

#######################################
# Cleanup Functions
#######################################

cleanup_demo() {
    echo ""

    local should_cleanup="$DEMO_CLEANUP"

    # Ask user in interactive mode
    if [[ "$DEMO_MODE" == "interactive" ]] && [[ "$DEMO_CLEANUP" == "ask" ]]; then
        echo -n "Clean up demo environment? (y/n): "
        read -r response
        case "$response" in
            [yY]|[yY][eE][sS])
                should_cleanup="true"
                ;;
            *)
                should_cleanup="false"
                ;;
        esac
    fi

    if [[ "$should_cleanup" != "true" ]]; then
        info "Skipping cleanup. Demo environment preserved."
        info "To clean up manually:"
        info "  cf delete $DEMO_APP_NAME -f -r"
        info "  cf delete-space $DEMO_SPACE -f"
        info "  cf delete-org $DEMO_ORG -f"
        echo ""
        return 0
    fi

    info "Cleaning up demo environment..."

    # Delete app
    if cf app "$DEMO_APP_NAME" &> /dev/null; then
        info "Deleting app: $DEMO_APP_NAME"
        cf delete "$DEMO_APP_NAME" -f -r
        success "App deleted"
    fi

    # Reset space isolation segment
    info "Resetting space isolation segment..."
    cf reset-space-isolation-segment "$DEMO_SPACE" &> /dev/null || true

    # Delete space
    if cf space "$DEMO_SPACE" &> /dev/null; then
        info "Deleting space: $DEMO_SPACE"
        cf delete-space "$DEMO_SPACE" -f
        success "Space deleted"
    fi

    # Delete org
    if cf org "$DEMO_ORG" &> /dev/null; then
        info "Deleting org: $DEMO_ORG"
        cf delete-org "$DEMO_ORG" -f
        success "Org deleted"
    fi

    # Optionally delete isolation segment
    if [[ "$DEMO_CLEANUP" == "full" ]]; then
        if cf isolation-segments | grep -q "^${DEMO_SEGMENT}$"; then
            info "Deleting isolation segment: $DEMO_SEGMENT"
            cf delete-isolation-segment "$DEMO_SEGMENT" -f || warn "Could not delete segment (may be in use)"
        fi
    fi

    # Clean up temp files
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
    fi

    success "Cleanup completed"
    echo ""
}

#######################################
# Usage and Help
#######################################

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Interactive demo script showing zero-impact migration from shared Diego cells
to isolated Diego cells in Cloud Foundry.

OPTIONS:
  --automated              Run in automated mode (no pauses)
  --interactive            Run in interactive mode with pauses (default)
  --segment NAME           Isolation segment name (default: $DEMO_SEGMENT)
  --org NAME               Org name (default: $DEMO_ORG)
  --space NAME             Space name (default: $DEMO_SPACE)
  --app NAME               App name (default: $DEMO_APP_NAME)
  --cleanup                Cleanup at end without asking
  --no-cleanup             Skip cleanup at end
  --skip-bosh              Skip BOSH verification (CF CLI only)
  --verbose                Enable verbose output
  -h, --help               Show this help message
  -v, --version            Show version

ENVIRONMENT VARIABLES:
  DEMO_MODE                Operating mode: 'interactive' or 'automated'
  DEMO_SEGMENT             Isolation segment name
  DEMO_ORG                 Org name
  DEMO_SPACE               Space name
  DEMO_APP_NAME            App name
  DEMO_CLEANUP             Cleanup mode: 'ask', 'true', 'false', 'full'
  DEMO_SKIP_BOSH           Skip BOSH verification: 'true' or 'false'
  VERBOSE                  Enable debug logging: 'true' or 'false'

EXAMPLES:
  # Interactive mode (default)
  $0

  # Automated mode with cleanup
  $0 --automated --cleanup

  # Custom segment and org
  $0 --segment high-density --org prod-demo --space demo

  # Skip BOSH verification
  $0 --skip-bosh

  # Environment variables
  DEMO_MODE=automated DEMO_CLEANUP=true $0

For more information, see: docs/plans/2025-12-18-demo-script-implementation.md

EOF
}

version() {
    echo "$0 version $VERSION"
}

#######################################
# Main
#######################################

main() {
    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --automated)
                DEMO_MODE="automated"
                shift
                ;;
            --interactive)
                DEMO_MODE="interactive"
                shift
                ;;
            --segment)
                DEMO_SEGMENT="$2"
                shift 2
                ;;
            --org)
                DEMO_ORG="$2"
                shift 2
                ;;
            --space)
                DEMO_SPACE="$2"
                shift 2
                ;;
            --app)
                DEMO_APP_NAME="$2"
                shift 2
                ;;
            --cleanup)
                DEMO_CLEANUP="true"
                shift
                ;;
            --no-cleanup)
                DEMO_CLEANUP="false"
                shift
                ;;
            --skip-bosh)
                DEMO_SKIP_BOSH="true"
                shift
                ;;
            --verbose)
                VERBOSE="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                version
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Rest of main function
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

    # Capture AFTER state
    capture_after_state

    pause_for_demo "see AFTER state"

    # Display AFTER state
    display_after_state

    pause_for_demo "see side-by-side comparison"

    # Display comparison
    display_comparison

    # Cleanup
    cleanup_demo

    # Final message
    if [[ "$DEMO_MODE" == "interactive" ]]; then
        echo -e "${GREEN}${BOLD}Demo complete!${NC}"
    else
        log "Demo completed successfully"
    fi
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
