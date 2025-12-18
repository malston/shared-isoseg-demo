#!/usr/bin/env bash
# ABOUTME: Tile-based isolation segment management for Cloud Foundry / TAS / EAR
# ABOUTME: SUPPORTED by Broadcom - uses Isolation Segment tile via Ops Manager

set -euo pipefail

# Script version
VERSION="1.0.0"

# Default configuration (can be overridden via environment variables)
: "${CF_API:=}"
: "${CF_USERNAME:=}"
: "${CF_PASSWORD:=}"
: "${OM_TARGET:=}"
: "${OM_USERNAME:=}"
: "${OM_PASSWORD:=}"
: "${OM_SKIP_SSL_VALIDATION:=false}"
: "${PIVNET_TOKEN:=}"
: "${DRY_RUN:=false}"
: "${VERBOSE:=false}"
: "${LOG_FILE:=/tmp/isolation-segment-tile.log}"

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
Usage: $0 COMMAND [OPTIONS]

Tile-based isolation segment management for Cloud Foundry / TAS / EAR.
Uses the official Isolation Segment tile - SUPPORTED by Broadcom.

COMMANDS:
    download-tile       Download Isolation Segment tile from Pivnet
    install-tile        Install Isolation Segment tile (upload and stage)
    configure-segment   Configure a deployed isolation segment tile
    register-segment    Register segment in Cloud Controller
    help                Show this help message

OPTIONS:
    -h, --help         Show this help message
    -v, --version      Show script version
    --verbose          Enable verbose output
    --dry-run          Show what would be done without executing

ENVIRONMENT VARIABLES (required):
    OM_TARGET          Ops Manager URL
    OM_USERNAME        Ops Manager username
    OM_PASSWORD        Ops Manager password
    CF_API             Cloud Foundry API endpoint
    CF_USERNAME        Cloud Foundry username
    CF_PASSWORD        Cloud Foundry password

OPTIONAL ENVIRONMENT VARIABLES:
    PIVNET_TOKEN            Pivotal Network API token (for download-tile)
    OM_SKIP_SSL_VALIDATION  Skip SSL validation (default: false)
    DRY_RUN                 Preview mode (default: false)
    VERBOSE                 Debug logging (default: false)

EXAMPLES:
    # Download tile from Pivnet
    $0 download-tile --version 10.2 --output-directory ~/Downloads

    # Install tile
    $0 install-tile --tile-path ~/Downloads/isolation-segment-10.2.x.pivotal

    # Configure and deploy
    $0 configure-segment --name high-density --cell-count 120

    # Register in CF
    $0 register-segment --name high-density

DOWNLOAD TILES:
    https://support.broadcom.com/group/ecx/productdownloads?subfamily=Isolation%20Segmentation%20for%20VMware%20Tanzu%20Platform

DOCUMENTATION:
    https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/6-0/eart/installing-pcf-is.html

EOF
}

version() {
    echo "$0 version $VERSION"
    echo "Tile-based installation - SUPPORTED by Broadcom"
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
        fatal "Not connected to Cloud Foundry. Run 'cf api' first or set CF_API."
    fi

    if ! cf target &> /dev/null; then
        fatal "Not authenticated to Cloud Foundry. Run 'cf login' or set CF_USERNAME/CF_PASSWORD."
    fi

    success "Cloud Foundry connection validated"
}

validate_om_connection() {
    info "Validating Ops Manager connection..."

    [[ -z "$OM_TARGET" ]] && fatal "OM_TARGET environment variable not set"

    if ! om curl --path /api/v0/info &> /dev/null; then
        fatal "Cannot connect to Ops Manager at $OM_TARGET. Check OM_* environment variables."
    fi

    success "Ops Manager connection validated"
}

#######################################
# Download Tile Command
#######################################

download_tile_usage() {
    cat <<EOF
Usage: $0 download-tile [OPTIONS]

Download the Isolation Segment tile from Pivotal Network (Pivnet).

OPTIONS:
    --version VERSION        Major.minor version (e.g., 10.2, 6.0) (required)
    --output-directory DIR   Download location (default: ~/Downloads)
    -h, --help               Show this help message

EXAMPLES:
    # Download EAR 10.2.x tile
    $0 download-tile --version 10.2

    # Download to specific directory
    $0 download-tile --version 6.0 --output-directory /tmp

REQUIREMENTS:
    - PIVNET_TOKEN environment variable must be set

EOF
}

download_tile() {
    local version=""
    local output_dir="${HOME}/Downloads"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                version="$2"
                shift 2
                ;;
            --output-directory)
                output_dir="$2"
                shift 2
                ;;
            -h|--help)
                download_tile_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                download_tile_usage
                exit 1
                ;;
        esac
    done

    # Validate arguments
    [[ -z "$version" ]] && fatal "Version is required. Use --version VERSION (e.g., 10.2 or 6.0)"
    [[ -z "$PIVNET_TOKEN" ]] && fatal "PIVNET_TOKEN environment variable not set"

    # Create output directory if needed
    mkdir -p "$output_dir" || fatal "Failed to create output directory: $output_dir"

    info "Downloading Isolation Segment tile from Pivnet"
    info "  Version: $version.x (latest patch)"
    info "  Output: $output_dir"

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN: Would download p-isolation-segment ${version}.x to $output_dir"
        return 0
    fi

    # Validate om command
    require_command om

    # Download tile using om
    info "Downloading tile (this may take several minutes)..."

    if om download-product \
        --pivnet-product-slug='p-isolation-segment' \
        --file-glob="p-isolation-segment-${version}.[0-9]*.*" \
        --product-version-regex="^${version}\.[0-9]*.*" \
        --output-directory="$output_dir" \
        --pivnet-api-token="$PIVNET_TOKEN"; then

        success "Tile downloaded successfully"

        # Find the downloaded file
        local downloaded_file
        downloaded_file=$(find "$output_dir" -name "p-isolation-segment-${version}.*.pivotal" -type f -print -quit 2>/dev/null)

        if [[ -n "$downloaded_file" ]]; then
            success "Downloaded: $downloaded_file"
            info ""
            info "Next step: Install the tile"
            info "  $0 install-tile --tile-path \"$downloaded_file\""
        else
            warn "Tile downloaded but could not locate file in $output_dir"
        fi
    else
        fatal "Failed to download tile. Check PIVNET_TOKEN and network connection."
    fi
}

#######################################
# Install Tile Command
#######################################

install_tile_usage() {
    cat <<EOF
Usage: $0 install-tile [OPTIONS]

Install the Isolation Segment tile to Ops Manager.

OPTIONS:
    --tile-path PATH    Path to isolation segment .pivotal file (required)
    -h, --help          Show this help message

EXAMPLE:
    $0 install-tile --tile-path ~/Downloads/isolation-segment-6.0.15.pivotal

DOWNLOAD TILE:
    https://support.broadcom.com/group/ecx/productdownloads?subfamily=Isolation%20Segmentation%20for%20VMware%20Tanzu%20Platform

EOF
}

install_tile() {
    local tile_path=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --tile-path)
                tile_path="$2"
                shift 2
                ;;
            -h|--help)
                install_tile_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                install_tile_usage
                exit 1
                ;;
        esac
    done

    # Validate arguments
    [[ -z "$tile_path" ]] && fatal "Tile path is required. Use --tile-path PATH"
    [[ ! -f "$tile_path" ]] && fatal "Tile file not found: $tile_path"

    info "Installing Isolation Segment tile from: $tile_path"

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN: Would install tile from $tile_path"
        return 0
    fi

    # Validate OM connection
    validate_om_connection
    require_command om

    # Upload tile
    info "Uploading tile to Ops Manager..."
    if om upload-product --product "$tile_path"; then
        success "Tile uploaded successfully"
    else
        fatal "Failed to upload tile"
    fi

    # Extract version from filename
    local tile_version
    tile_version=$(basename "$tile_path" | grep -oP 'isolation-segment-\K[0-9]+\.[0-9]+\.[0-9]+' || echo "")

    if [[ -z "$tile_version" ]]; then
        warn "Could not auto-detect tile version from filename"
        info "Manually stage the tile using: om stage-product --product-name isolation-segment --product-version VERSION"
    else
        info "Staging tile version $tile_version..."
        if om stage-product --product-name isolation-segment --product-version "$tile_version"; then
            success "Tile staged successfully"
        else
            error "Failed to stage tile. Stage manually via Ops Manager UI."
            return 1
        fi
    fi

    success "Tile installed and staged"
    info "Next steps:"
    info "  1. Configure the tile: $0 configure-segment --name SEGMENT_NAME --cell-count COUNT"
    info "  2. Apply changes in Ops Manager"
    info "  3. Register segment: $0 register-segment --name SEGMENT_NAME"
}

#######################################
# Configure Segment Command
#######################################

configure_segment_usage() {
    cat <<EOF
Usage: $0 configure-segment [OPTIONS]

Configure the Isolation Segment tile for deployment.

OPTIONS:
    --name NAME         Segment name (required, must match placement tag)
    --cell-count COUNT  Number of Diego cells (required)
    --network NETWORK   Network for isolation segment VMs (optional)
    --az AZ1,AZ2,AZ3    Availability zones (comma-separated, optional)
    -h, --help          Show this help message

EXAMPLE:
    $0 configure-segment --name high-density --cell-count 120

NOTE:
    This command sets basic configuration. For advanced configuration
    (networks, AZs, load balancers, routing), use Ops Manager UI or
    om configure-product with a complete configuration file.

EOF
}

configure_segment() {
    local name=""
    local cell_count=""
    local network=""
    local azs=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)
                name="$2"
                shift 2
                ;;
            --cell-count)
                cell_count="$2"
                shift 2
                ;;
            --network)
                network="$2"
                shift 2
                ;;
            --az)
                azs="$2"
                shift 2
                ;;
            -h|--help)
                configure_segment_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                configure_segment_usage
                exit 1
                ;;
        esac
    done

    # Validate arguments
    [[ -z "$name" ]] && fatal "Segment name is required. Use --name NAME"
    [[ -z "$cell_count" ]] && fatal "Cell count is required. Use --cell-count COUNT"

    info "Configuring Isolation Segment tile"
    info "  Segment name: $name"
    info "  Cell count: $cell_count"
    [[ -n "$network" ]] && info "  Network: $network"
    [[ -n "$azs" ]] && info "  AZs: $azs"

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN: Would configure tile with segment name=$name, cells=$cell_count"
        return 0
    fi

    # Validate OM connection
    validate_om_connection

    warn "⚠️  MANUAL CONFIGURATION REQUIRED"
    warn ""
    warn "Complete tile configuration via Ops Manager UI:"
    warn "  1. Go to Ops Manager → Isolation Segment Tile"
    warn "  2. Set Segment Name: $name"
    warn "  3. Set Diego Cell Instances: $cell_count"
    [[ -n "$network" ]] && warn "  4. Assign Network: $network"
    [[ -n "$azs" ]] && warn "  5. Configure AZs: $azs"
    warn "  6. Configure Networking (shared vs dedicated routing)"
    warn "  7. Save configuration"
    warn ""
    warn "Then apply changes:"
    warn "  Via UI: Review Pending Changes → Apply Changes"
    warn "  Via CLI: om apply-changes --product-name isolation-segment"
    warn ""

    info "After deployment completes, register the segment:"
    info "  $0 register-segment --name $name"
}

#######################################
# Register Segment Command
#######################################

register_segment_usage() {
    cat <<EOF
Usage: $0 register-segment [OPTIONS]

Register the isolation segment in Cloud Controller after tile deployment.

OPTIONS:
    --name NAME         Segment name (required, must match tile configuration)
    -h, --help          Show this help message

EXAMPLE:
    $0 register-segment --name high-density

NOTE:
    Run this AFTER the Isolation Segment tile has been deployed via
    Ops Manager. The segment name must match the name configured in
    the tile's Segment Name property.

EOF
}

register_segment() {
    local name=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)
                name="$2"
                shift 2
                ;;
            -h|--help)
                register_segment_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                register_segment_usage
                exit 1
                ;;
        esac
    done

    # Validate arguments
    [[ -z "$name" ]] && fatal "Segment name is required. Use --name NAME"

    info "Registering isolation segment: $name"

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN: Would register segment $name in Cloud Controller"
        return 0
    fi

    # Validate CF connection
    validate_cf_connection

    # Check if segment already exists
    if cf isolation-segments | grep -q "^${name}$"; then
        warn "Segment $name already registered in Cloud Controller"
        return 0
    fi

    # Register segment
    if cf create-isolation-segment "$name"; then
        success "Segment $name registered successfully"
    else
        fatal "Failed to register segment in Cloud Controller"
    fi

    info "Segment $name is now ready for use"
    info ""
    info "Next steps to assign apps to this segment:"
    info "  1. Entitle org: cf enable-org-isolation ORG_NAME $name"
    info "  2. Set org default (optional): cf set-org-default-isolation-segment ORG_NAME $name"
    info "  3. Assign space: cf set-space-isolation-segment SPACE_NAME $name"
    info "  4. Restart apps: cf restart APP_NAME"
}

#######################################
# Main
#######################################

main() {
    # Check for required commands
    require_command cf
    require_command om

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
            download-tile|install-tile|configure-segment|register-segment|help)
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
        download-tile)
            download_tile "$@"
            ;;
        install-tile)
            install_tile "$@"
            ;;
        configure-segment)
            configure_segment "$@"
            ;;
        register-segment)
            register_segment "$@"
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
