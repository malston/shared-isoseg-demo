#!/usr/bin/env bash
# ABOUTME: Comprehensive isolation segment migration script for Cloud Foundry / TAS / EAR
# ABOUTME: Supports creating segments, batch migrations, monitoring, and rollback operations

set -euo pipefail

# Script version
VERSION="1.0.0"

# Default configuration (can be overridden via environment variables)
: "${CF_API:=}"
: "${CF_USERNAME:=}"
: "${CF_PASSWORD:=}"
: "${BOSH_ENVIRONMENT:=}"
: "${BOSH_CLIENT:=}"
: "${BOSH_CLIENT_SECRET:=}"
: "${BOSH_CA_CERT:=}"
: "${BATCH_SIZE:=10}"
: "${MIGRATION_DELAY:=30}"
: "${DRY_RUN:=false}"
: "${VERBOSE:=false}"
: "${LOG_FILE:=/tmp/isolation-segment-migration.log}"

# Colors for output (disable if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

#######################################
# Utility Functions
#######################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}INFO: $*${NC}" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}SUCCESS: $*${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}WARNING: $*${NC}" | tee -a "$LOG_FILE" >&2
}

error() {
    echo -e "${RED}ERROR: $*${NC}" | tee -a "$LOG_FILE" >&2
}

fatal() {
    error "$@"
    exit 1
}

debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        log "DEBUG" "$@"
    fi
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] COMMAND [ARGS]

Comprehensive isolation segment migration tool for Cloud Foundry / TAS / EAR.

COMMANDS:
    create-segment      Create and configure a new isolation segment
    migrate            Migrate apps to isolation segment in batches
    monitor            Monitor segment capacity and performance
    rollback           Rollback app migrations to previous segment
    validate           Validate segment configuration and capacity
    help               Show this help message

OPTIONS:
    -h, --help         Show this help message
    -v, --version      Show script version
    --verbose          Enable verbose output
    --dry-run          Show what would be done without executing
    --log-file FILE    Log file path (default: $LOG_FILE)

ENVIRONMENT VARIABLES (for sensitive data):
    CF_API             Cloud Foundry API endpoint
    CF_USERNAME        Cloud Foundry username
    CF_PASSWORD        Cloud Foundry password
    BOSH_ENVIRONMENT   BOSH Director environment
    BOSH_CLIENT        BOSH client ID
    BOSH_CLIENT_SECRET BOSH client secret
    BOSH_CA_CERT       BOSH CA certificate path
    BATCH_SIZE         Number of apps to migrate per batch (default: 10)
    MIGRATION_DELAY    Seconds to wait between app restarts (default: 30)

EXAMPLES:
    # Create a high-density isolation segment
    $0 create-segment --name high-density --cell-size 8/64 --count 120

    # Migrate apps in production space to high-density segment
    $0 migrate --org production-org --space prod-space --segment high-density

    # Monitor segment capacity and performance
    $0 monitor --segment high-density --deployment cf

    # Rollback migration if issues occur
    $0 rollback --org production-org --space prod-space

    # Validate segment configuration
    $0 validate --segment high-density --deployment high-density

For detailed help on a specific command:
    $0 COMMAND --help

EOF
}

version() {
    echo "$0 version $VERSION"
}

#######################################
# Validation Functions
#######################################

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        fatal "Required command '$cmd' not found. Please install it and try again."
    fi
}

validate_cf_connection() {
    info "Validating Cloud Foundry connection..."

    if ! cf api &> /dev/null; then
        fatal "Not connected to Cloud Foundry. Run 'cf api' first or set CF_API environment variable."
    fi

    if ! cf target &> /dev/null; then
        fatal "Not authenticated to Cloud Foundry. Run 'cf login' first or set CF_USERNAME and CF_PASSWORD."
    fi

    success "Cloud Foundry connection validated"
}

validate_bosh_connection() {
    info "Validating BOSH connection..."

    if [[ -z "$BOSH_ENVIRONMENT" ]]; then
        fatal "BOSH_ENVIRONMENT not set. Please set it to your BOSH Director URL."
    fi

    if ! bosh env &> /dev/null; then
        fatal "Cannot connect to BOSH Director. Check BOSH_* environment variables."
    fi

    success "BOSH connection validated"
}

validate_segment_exists() {
    local segment="$1"

    if ! cf isolation-segments | grep -q "^${segment}$"; then
        return 1
    fi
    return 0
}

validate_org_exists() {
    local org="$1"

    if ! cf orgs | grep -q "^${org}$"; then
        return 1
    fi
    return 0
}

validate_space_exists() {
    local org="$1"
    local space="$2"

    cf target -o "$org" &> /dev/null || return 1

    if ! cf spaces | grep -q "^${space}$"; then
        return 1
    fi
    return 0
}

#######################################
# Create Segment Command
#######################################

create_segment_usage() {
    cat <<EOF
Usage: $0 create-segment [OPTIONS]

Create and configure a new isolation segment with BOSH deployment.

OPTIONS:
    --name NAME              Segment name (required)
    --cell-size SIZE         Diego cell size: 4/32, 8/64, 4/128, 8/32 (required)
    --count COUNT            Number of Diego cells to deploy (required)
    --deployment NAME        BOSH deployment name (default: same as segment name)
    --az AZ1,AZ2,AZ3        Availability zones (comma-separated)
    --network NETWORK        BOSH network name (default: default)
    --vm-type TYPE          VM type for Diego cells (default: auto-calculated from cell-size)
    --register              Register segment in Cloud Controller after creation
    -h, --help              Show this help message

EXAMPLES:
    # Create high-density segment with 120 cells at 8/64
    $0 create-segment --name high-density --cell-size 8/64 --count 120 --register

    # Create high-memory segment with 30 cells at 4/128
    $0 create-segment --name high-memory --cell-size 4/128 --count 30 --az us-east-1a,us-east-1b,us-east-1c

EOF
}

create_segment() {
    local name=""
    local cell_size=""
    local count=""
    local deployment=""
    local azs=""
    local network="default"
    local vm_type=""
    local register=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)
                name="$2"
                shift 2
                ;;
            --cell-size)
                cell_size="$2"
                shift 2
                ;;
            --count)
                count="$2"
                shift 2
                ;;
            --deployment)
                deployment="$2"
                shift 2
                ;;
            --az)
                azs="$2"
                shift 2
                ;;
            --network)
                network="$2"
                shift 2
                ;;
            --vm-type)
                vm_type="$2"
                shift 2
                ;;
            --register)
                register=true
                shift
                ;;
            -h|--help)
                create_segment_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                create_segment_usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    [[ -z "$name" ]] && fatal "Segment name is required. Use --name NAME"
    [[ -z "$cell_size" ]] && fatal "Cell size is required. Use --cell-size SIZE (e.g., 8/64)"
    [[ -z "$count" ]] && fatal "Cell count is required. Use --count COUNT"

    # Default deployment name to segment name
    deployment="${deployment:-$name}"

    info "Creating isolation segment: $name"
    info "  Cell size: $cell_size"
    info "  Cell count: $count"
    info "  Deployment: $deployment"

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN: Would create segment $name with $count cells at $cell_size"
        return 0
    fi

    # Validate BOSH connection
    validate_bosh_connection

    # Parse cell size
    local vcpu memory
    IFS='/' read -r vcpu memory <<< "$cell_size"

    # Auto-calculate VM type if not provided
    if [[ -z "$vm_type" ]]; then
        vm_type="diego-cell-${vcpu}cpu-${memory}gb"
        info "Auto-calculated VM type: $vm_type"
    fi

    # Generate BOSH manifest (simplified - in production, use a template)
    info "Generating BOSH manifest for deployment $deployment..."

    cat > "/tmp/${deployment}-manifest.yml" <<MANIFEST
---
name: $deployment

instance_groups:
- name: diego_cell
  instances: $count
  azs: [${azs:-z1,z2,z3}]
  jobs:
  - name: rep
    release: diego
    properties:
      diego:
        rep:
          placement_tags:
          - $name
  vm_type: $vm_type
  stemcell: default
  networks:
  - name: $network

releases:
- name: diego
  version: latest

stemcells:
- alias: default
  os: ubuntu-jammy
  version: latest

update:
  canaries: 1
  max_in_flight: 10
  canary_watch_time: 30000-600000
  update_watch_time: 5000-600000
MANIFEST

    success "Generated manifest at /tmp/${deployment}-manifest.yml"

    # Deploy via BOSH
    info "Deploying $deployment..."
    if bosh -e "$BOSH_ENVIRONMENT" -d "$deployment" deploy "/tmp/${deployment}-manifest.yml" --non-interactive; then
        success "BOSH deployment $deployment created successfully"
    else
        fatal "BOSH deployment failed. Check logs for details."
    fi

    # Register in Cloud Controller
    if [[ "$register" == "true" ]]; then
        info "Registering segment $name in Cloud Controller..."
        validate_cf_connection

        if validate_segment_exists "$name"; then
            warn "Segment $name already exists in Cloud Controller"
        else
            if cf create-isolation-segment "$name"; then
                success "Segment $name registered in Cloud Controller"
            else
                error "Failed to register segment in Cloud Controller"
            fi
        fi
    fi

    success "Isolation segment $name created successfully"
}

#######################################
# Migrate Command
#######################################

migrate_usage() {
    cat <<EOF
Usage: $0 migrate [OPTIONS]

Migrate applications to an isolation segment in batches with monitoring.

OPTIONS:
    --org ORG               Organization name (required)
    --space SPACE           Space name (required)
    --segment SEGMENT       Target isolation segment name (required)
    --batch-size SIZE       Number of apps to migrate per batch (default: $BATCH_SIZE)
    --delay SECONDS         Delay between app restarts in seconds (default: $MIGRATION_DELAY)
    --apps APP1,APP2,...    Comma-separated list of specific apps to migrate (optional)
    --exclude APP1,APP2,... Comma-separated list of apps to exclude (optional)
    --entitle               Entitle org to segment before migration
    -h, --help              Show this help message

EXAMPLES:
    # Migrate all apps in production space to high-density segment
    $0 migrate --org production-org --space prod-space --segment high-density --entitle

    # Migrate specific apps only
    $0 migrate --org prod-org --space prod-space --segment high-density --apps app1,app2,app3

    # Migrate in smaller batches with longer delays
    $0 migrate --org prod-org --space prod-space --segment high-density --batch-size 5 --delay 60

EOF
}

migrate() {
    local org=""
    local space=""
    local segment=""
    local batch_size="$BATCH_SIZE"
    local delay="$MIGRATION_DELAY"
    local apps_filter=""
    local exclude_filter=""
    local entitle=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --org)
                org="$2"
                shift 2
                ;;
            --space)
                space="$2"
                shift 2
                ;;
            --segment)
                segment="$2"
                shift 2
                ;;
            --batch-size)
                batch_size="$2"
                shift 2
                ;;
            --delay)
                delay="$2"
                shift 2
                ;;
            --apps)
                apps_filter="$2"
                shift 2
                ;;
            --exclude)
                exclude_filter="$2"
                shift 2
                ;;
            --entitle)
                entitle=true
                shift
                ;;
            -h|--help)
                migrate_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                migrate_usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    [[ -z "$org" ]] && fatal "Organization is required. Use --org ORG"
    [[ -z "$space" ]] && fatal "Space is required. Use --space SPACE"
    [[ -z "$segment" ]] && fatal "Segment is required. Use --segment SEGMENT"

    validate_cf_connection

    # Validate org and space exist
    validate_org_exists "$org" || fatal "Organization '$org' not found"
    validate_space_exists "$org" "$space" || fatal "Space '$space' not found in org '$org'"

    # Validate segment exists
    validate_segment_exists "$segment" || fatal "Isolation segment '$segment' not found"

    info "Starting migration to isolation segment: $segment"
    info "  Organization: $org"
    info "  Space: $space"
    info "  Batch size: $batch_size"
    info "  Delay between restarts: ${delay}s"

    # Entitle org if requested
    if [[ "$entitle" == "true" ]]; then
        info "Entitling org $org to segment $segment..."
        if cf enable-org-isolation "$org" "$segment"; then
            success "Org $org entitled to segment $segment"
        else
            error "Failed to entitle org. Continuing anyway..."
        fi
    fi

    # Target the space
    cf target -o "$org" -s "$space" &> /dev/null

    # Get list of apps
    info "Fetching app list from space $space..."
    local apps
    apps=$(cf apps | tail -n +4 | awk '{print $1}' | grep -v '^$')

    if [[ -z "$apps" ]]; then
        warn "No apps found in space $space"
        return 0
    fi

    # Filter apps if requested
    if [[ -n "$apps_filter" ]]; then
        info "Filtering to specific apps: $apps_filter"
        IFS=',' read -ra FILTER_APPS <<< "$apps_filter"
        apps=$(echo "$apps" | grep -E "^($(IFS='|'; echo "${FILTER_APPS[*]}"))$" || true)
    fi

    # Exclude apps if requested
    if [[ -n "$exclude_filter" ]]; then
        info "Excluding apps: $exclude_filter"
        IFS=',' read -ra EXCLUDE_APPS <<< "$exclude_filter"
        apps=$(echo "$apps" | grep -vE "^($(IFS='|'; echo "${EXCLUDE_APPS[*]}"))$" || true)
    fi

    local total_apps
    total_apps=$(echo "$apps" | wc -l | tr -d ' ')

    info "Found $total_apps apps to migrate"

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN: Would migrate the following apps:"
        echo "$apps"
        return 0
    fi

    # Assign space to isolation segment
    info "Assigning space $space to isolation segment $segment..."
    if cf set-space-isolation-segment "$space" "$segment"; then
        success "Space $space assigned to segment $segment"
    else
        fatal "Failed to assign space to segment"
    fi

    # Migrate apps in batches
    local batch_num=1
    local migrated=0
    local failed=0

    while IFS= read -r app; do
        [[ -z "$app" ]] && continue

        info "[$batch_num/$total_apps] Migrating app: $app"

        # Restart app to move to new segment
        if cf restart "$app" --strategy rolling 2>/dev/null || cf restart "$app"; then
            success "App $app migrated successfully"
            ((migrated++))

            # Verify app is in correct segment
            local app_segment
            app_segment=$(cf app "$app" | grep "isolation segment:" | awk '{print $3}')
            if [[ "$app_segment" == "$segment" ]]; then
                success "Verified app $app is in segment $segment"
            else
                warn "App $app restart succeeded but segment assignment unclear"
            fi
        else
            error "Failed to migrate app $app"
            ((failed++))
        fi

        # Delay between app restarts
        if [[ $batch_num -lt $total_apps ]]; then
            info "Waiting ${delay}s before next app..."
            sleep "$delay"
        fi

        ((batch_num++))
    done <<< "$apps"

    # Summary
    echo ""
    success "Migration complete"
    info "  Total apps: $total_apps"
    info "  Migrated: $migrated"
    info "  Failed: $failed"

    if [[ $failed -gt 0 ]]; then
        warn "Some apps failed to migrate. Review logs and consider rollback."
        return 1
    fi

    return 0
}

#######################################
# Monitor Command
#######################################

monitor_usage() {
    cat <<EOF
Usage: $0 monitor [OPTIONS]

Monitor isolation segment capacity, utilization, and performance.

OPTIONS:
    --segment SEGMENT       Isolation segment name (required)
    --deployment DEPLOY     BOSH deployment name (default: same as segment)
    --watch SECONDS         Watch mode: refresh every N seconds
    --output FORMAT         Output format: text, json, csv (default: text)
    -h, --help              Show this help message

EXAMPLES:
    # Monitor high-density segment capacity
    $0 monitor --segment high-density

    # Watch segment in real-time (refresh every 10 seconds)
    $0 monitor --segment high-density --watch 10

    # Export capacity data as JSON
    $0 monitor --segment high-density --output json

EOF
}

monitor() {
    local segment=""
    local deployment=""
    local watch_interval=""
    local output_format="text"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --segment)
                segment="$2"
                shift 2
                ;;
            --deployment)
                deployment="$2"
                shift 2
                ;;
            --watch)
                watch_interval="$2"
                shift 2
                ;;
            --output)
                output_format="$2"
                shift 2
                ;;
            -h|--help)
                monitor_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                monitor_usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    [[ -z "$segment" ]] && fatal "Segment is required. Use --segment SEGMENT"

    deployment="${deployment:-$segment}"

    validate_cf_connection
    validate_segment_exists "$segment" || fatal "Segment '$segment' not found"

    # Function to gather metrics
    gather_metrics() {
        info "Gathering metrics for segment: $segment"

        # Get apps in segment
        local app_count
        app_count=$(cf curl "/v3/apps?isolation_segment_guids=$(cf isolation-segment "$segment" --guid)" 2>/dev/null | jq -r '.pagination.total_results' 2>/dev/null || echo "0")

        # Get Diego cell capacity (requires BOSH)
        local cell_count=0
        local total_memory=0
        local available_memory=0
        local total_disk=0
        local available_disk=0
        local total_containers=0
        local available_containers=0

        if [[ -n "$BOSH_ENVIRONMENT" ]] && bosh env &> /dev/null; then
            # Get cell count
            cell_count=$(bosh -e "$BOSH_ENVIRONMENT" -d "$deployment" instances --json 2>/dev/null | jq -r '.Tables[0].Rows | length' 2>/dev/null || echo "0")

            # Get capacity from first cell (representative)
            if [[ $cell_count -gt 0 ]]; then
                local capacity_data
                capacity_data=$(bosh -e "$BOSH_ENVIRONMENT" -d "$deployment" ssh diego_cell/0 -c "curl -s localhost:1800/state" 2>/dev/null || echo "{}")

                available_memory=$(echo "$capacity_data" | jq -r '.AvailableResources.MemoryMB // 0' 2>/dev/null)
                available_disk=$(echo "$capacity_data" | jq -r '.AvailableResources.DiskMB // 0' 2>/dev/null)
                available_containers=$(echo "$capacity_data" | jq -r '.AvailableResources.Containers // 0' 2>/dev/null)

                # Estimate totals (assuming cells are similar)
                total_memory=$((available_memory * cell_count))
                total_disk=$((available_disk * cell_count))
                total_containers=$((available_containers * cell_count))
            fi
        fi

        # Calculate utilization
        local memory_used=$((total_memory > 0 ? total_memory - available_memory : 0))
        local memory_pct=$((total_memory > 0 ? (memory_used * 100) / total_memory : 0))

        # Output based on format
        case $output_format in
            json)
                cat <<JSON
{
  "segment": "$segment",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "apps": {
    "count": $app_count
  },
  "cells": {
    "count": $cell_count
  },
  "capacity": {
    "memory_mb": {
      "total": $total_memory,
      "available": $available_memory,
      "used": $memory_used,
      "utilization_pct": $memory_pct
    },
    "disk_mb": {
      "total": $total_disk,
      "available": $available_disk
    },
    "containers": {
      "total": $total_containers,
      "available": $available_containers
    }
  }
}
JSON
                ;;
            csv)
                echo "timestamp,segment,app_count,cell_count,memory_total_mb,memory_available_mb,memory_used_mb,memory_utilization_pct"
                echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$segment,$app_count,$cell_count,$total_memory,$available_memory,$memory_used,$memory_pct"
                ;;
            text|*)
                cat <<TEXT

=================================================
Isolation Segment Metrics: $segment
=================================================
Timestamp: $(date)

Apps:
  Total in segment: $app_count

Diego Cells:
  Count: $cell_count

Capacity:
  Memory (MB):
    Total:        $total_memory
    Available:    $available_memory
    Used:         $memory_used
    Utilization:  ${memory_pct}%

  Disk (MB):
    Total:        $total_disk
    Available:    $available_disk

  Containers:
    Total:        $total_containers
    Available:    $available_containers

=================================================
TEXT
                ;;
        esac
    }

    # Watch mode or single run
    if [[ -n "$watch_interval" ]]; then
        info "Watch mode enabled. Press Ctrl+C to exit."
        while true; do
            clear
            gather_metrics
            sleep "$watch_interval"
        done
    else
        gather_metrics
    fi
}

#######################################
# Rollback Command
#######################################

rollback_usage() {
    cat <<EOF
Usage: $0 rollback [OPTIONS]

Rollback app migrations by moving them back to the shared segment or a different segment.

OPTIONS:
    --org ORG               Organization name (required)
    --space SPACE           Space name (required)
    --target-segment NAME   Target segment to rollback to (default: shared/none)
    --apps APP1,APP2,...    Comma-separated list of specific apps to rollback (optional)
    --batch-size SIZE       Number of apps to rollback per batch (default: $BATCH_SIZE)
    --delay SECONDS         Delay between app restarts in seconds (default: $MIGRATION_DELAY)
    -h, --help              Show this help message

EXAMPLES:
    # Rollback all apps in space to shared segment
    $0 rollback --org production-org --space prod-space

    # Rollback specific apps only
    $0 rollback --org prod-org --space prod-space --apps app1,app2

    # Rollback to a different isolation segment
    $0 rollback --org prod-org --space prod-space --target-segment high-performance

EOF
}

rollback() {
    local org=""
    local space=""
    local target_segment=""
    local apps_filter=""
    local batch_size="$BATCH_SIZE"
    local delay="$MIGRATION_DELAY"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --org)
                org="$2"
                shift 2
                ;;
            --space)
                space="$2"
                shift 2
                ;;
            --target-segment)
                target_segment="$2"
                shift 2
                ;;
            --apps)
                apps_filter="$2"
                shift 2
                ;;
            --batch-size)
                batch_size="$2"
                shift 2
                ;;
            --delay)
                delay="$2"
                shift 2
                ;;
            -h|--help)
                rollback_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                rollback_usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    [[ -z "$org" ]] && fatal "Organization is required. Use --org ORG"
    [[ -z "$space" ]] && fatal "Space is required. Use --space SPACE"

    validate_cf_connection
    validate_org_exists "$org" || fatal "Organization '$org' not found"
    validate_space_exists "$org" "$space" || fatal "Space '$space' not found in org '$org'"

    info "Starting rollback for space: $space"
    info "  Organization: $org"
    if [[ -n "$target_segment" ]]; then
        info "  Target segment: $target_segment"
        validate_segment_exists "$target_segment" || fatal "Target segment '$target_segment' not found"
    else
        info "  Target: Shared segment (default)"
    fi

    # Target the space
    cf target -o "$org" -s "$space" &> /dev/null

    # Get current space segment
    local current_segment
    current_segment=$(cf space "$space" | grep "isolation segment:" | awk '{print $3}')

    if [[ -z "$current_segment" ]]; then
        warn "Space $space is not assigned to any isolation segment"
        return 0
    fi

    info "Current space segment: $current_segment"

    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ -n "$target_segment" ]]; then
            warn "DRY RUN: Would move space $space from $current_segment to $target_segment"
        else
            warn "DRY RUN: Would reset space $space from $current_segment to shared segment"
        fi
        return 0
    fi

    # Reset or reassign space
    if [[ -n "$target_segment" ]]; then
        info "Moving space to target segment $target_segment..."
        if cf set-space-isolation-segment "$space" "$target_segment"; then
            success "Space moved to segment $target_segment"
        else
            fatal "Failed to move space to target segment"
        fi
    else
        info "Resetting space to shared segment..."
        if cf reset-space-isolation-segment "$space"; then
            success "Space reset to shared segment"
        else
            fatal "Failed to reset space"
        fi
    fi

    # Get list of apps
    info "Fetching app list from space $space..."
    local apps
    apps=$(cf apps | tail -n +4 | awk '{print $1}' | grep -v '^$')

    if [[ -z "$apps" ]]; then
        warn "No apps found in space $space"
        return 0
    fi

    # Filter apps if requested
    if [[ -n "$apps_filter" ]]; then
        info "Filtering to specific apps: $apps_filter"
        IFS=',' read -ra FILTER_APPS <<< "$apps_filter"
        apps=$(echo "$apps" | grep -E "^($(IFS='|'; echo "${FILTER_APPS[*]}"))$" || true)
    fi

    local total_apps
    total_apps=$(echo "$apps" | wc -l | tr -d ' ')

    info "Found $total_apps apps to rollback"

    # Restart apps to apply new segment
    local batch_num=1
    local rolled_back=0
    local failed=0

    while IFS= read -r app; do
        [[ -z "$app" ]] && continue

        info "[$batch_num/$total_apps] Rolling back app: $app"

        if cf restart "$app" --strategy rolling 2>/dev/null || cf restart "$app"; then
            success "App $app rolled back successfully"
            ((rolled_back++))
        else
            error "Failed to rollback app $app"
            ((failed++))
        fi

        # Delay between app restarts
        if [[ $batch_num -lt $total_apps ]]; then
            info "Waiting ${delay}s before next app..."
            sleep "$delay"
        fi

        ((batch_num++))
    done <<< "$apps"

    # Summary
    echo ""
    success "Rollback complete"
    info "  Total apps: $total_apps"
    info "  Rolled back: $rolled_back"
    info "  Failed: $failed"

    if [[ $failed -gt 0 ]]; then
        warn "Some apps failed to rollback. Review logs for details."
        return 1
    fi

    return 0
}

#######################################
# Validate Command
#######################################

validate_usage() {
    cat <<EOF
Usage: $0 validate [OPTIONS]

Validate isolation segment configuration and capacity.

OPTIONS:
    --segment SEGMENT       Isolation segment name (required)
    --deployment DEPLOY     BOSH deployment name (default: same as segment)
    -h, --help              Show this help message

EXAMPLES:
    # Validate high-density segment configuration
    $0 validate --segment high-density

EOF
}

validate_cmd() {
    local segment=""
    local deployment=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --segment)
                segment="$2"
                shift 2
                ;;
            --deployment)
                deployment="$2"
                shift 2
                ;;
            -h|--help)
                validate_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                validate_usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    [[ -z "$segment" ]] && fatal "Segment is required. Use --segment SEGMENT"

    deployment="${deployment:-$segment}"

    info "Validating isolation segment: $segment"

    # Check CF registration
    info "Checking Cloud Foundry registration..."
    validate_cf_connection

    if validate_segment_exists "$segment"; then
        success "Segment $segment is registered in Cloud Controller"
    else
        error "Segment $segment is NOT registered in Cloud Controller"
        return 1
    fi

    # Check BOSH deployment
    if [[ -n "$BOSH_ENVIRONMENT" ]]; then
        info "Checking BOSH deployment..."
        validate_bosh_connection

        if bosh -e "$BOSH_ENVIRONMENT" -d "$deployment" deployment &> /dev/null; then
            success "BOSH deployment $deployment exists"

            # Check Diego cells
            local cell_count
            cell_count=$(bosh -e "$BOSH_ENVIRONMENT" -d "$deployment" instances --json 2>/dev/null | jq -r '.Tables[0].Rows | length' 2>/dev/null || echo "0")

            if [[ $cell_count -gt 0 ]]; then
                success "Found $cell_count Diego cells in deployment"

                # Verify placement tags
                info "Checking placement tags..."
                local placement_tags
                placement_tags=$(bosh -e "$BOSH_ENVIRONMENT" -d "$deployment" manifest | grep -A 2 "placement_tags:" | grep "^      -" | awk '{print $2}' | head -1)

                if [[ "$placement_tags" == "$segment" ]]; then
                    success "Placement tag matches segment name: $segment"
                else
                    error "Placement tag mismatch! Expected: $segment, Found: $placement_tags"
                    return 1
                fi
            else
                error "No Diego cells found in deployment"
                return 1
            fi
        else
            warn "BOSH deployment $deployment not found (this may be expected for externally managed deployments)"
        fi
    else
        warn "BOSH_ENVIRONMENT not set, skipping BOSH validation"
    fi

    success "Validation complete - segment $segment is properly configured"
}

#######################################
# Main
#######################################

main() {
    # Check for required commands
    require_command cf
    require_command jq

    # If BOSH commands are used, check for bosh
    if [[ -n "$BOSH_ENVIRONMENT" ]]; then
        require_command bosh
    fi

    # Parse global options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                version
                exit 0
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            create-segment|migrate|monitor|rollback|validate|help)
                # Command found
                break
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Get command
    local command="${1:-}"
    shift || true

    case $command in
        create-segment)
            create_segment "$@"
            ;;
        migrate)
            migrate "$@"
            ;;
        monitor)
            monitor "$@"
            ;;
        rollback)
            rollback "$@"
            ;;
        validate)
            validate_cmd "$@"
            ;;
        help|"")
            usage
            exit 0
            ;;
        *)
            error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
