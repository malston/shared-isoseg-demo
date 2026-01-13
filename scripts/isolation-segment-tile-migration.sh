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
    download-tile       Download Isolation Segment tile from Broadcom Support Portal
    download-replicator Download Replicator tool for creating multiple segment tiles
    replicate-tile      Create a new tile copy for an additional isolation segment
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
    # Download tile from Broadcom Support Portal
    $0 download-tile --version 6.0 --output-directory ~/Downloads

    # Download Replicator tool (for multiple isolation segments)
    $0 download-replicator --version 10.2.5+LTS-T --output-directory ~/Downloads

    # Create replicated tiles for multiple segments
    $0 replicate-tile --source ~/Downloads/p-isolation-segment-10.2.5.pivotal --name small-cell
    $0 replicate-tile --source ~/Downloads/p-isolation-segment-10.2.5.pivotal --name medium-cell
    $0 replicate-tile --source ~/Downloads/p-isolation-segment-10.2.5.pivotal --name large-cell

    # Install all tiles
    $0 install-tile --tile-path ~/Downloads/small-cell-10.2.5.pivotal
    $0 install-tile --tile-path ~/Downloads/medium-cell-10.2.5.pivotal
    $0 install-tile --tile-path ~/Downloads/large-cell-10.2.5.pivotal

    # Configure each segment using vars files
    $0 configure-segment --product small-cell --vars-file config/isolation-segment/small-cell-vars.yml
    $0 configure-segment --product medium-cell --vars-file config/isolation-segment/medium-cell-vars.yml
    $0 configure-segment --product large-cell --vars-file config/isolation-segment/large-cell-vars.yml

    # Apply changes in Ops Manager (or add --apply to configure-segment)
    om apply-changes

    # Register segments in CF
    $0 register-segment --name small-cell
    $0 register-segment --name medium-cell
    $0 register-segment --name large-cell

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
    --version VERSION        Version to download (required)
                            - Major.minor (e.g., 6.0, 10.2) downloads latest patch
                            - Full version (e.g., 6.0.23, 10.2.6) downloads specific patch
    --output-directory DIR   Download location (default: ~/Downloads)
    -h, --help               Show this help message

EXAMPLES:
    # Download latest 6.0.x LTS tile
    $0 download-tile --version 6.0

    # Download specific patch version
    $0 download-tile --version 6.0.23

    # Download to specific directory
    $0 download-tile --version 10.2.6 --output-directory /tmp

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
    [[ -z "$version" ]] && fatal "Version is required. Use --version VERSION (e.g., 10.2, 6.0.23)"
    [[ -z "$PIVNET_TOKEN" ]] && fatal "PIVNET_TOKEN environment variable not set"

    # Create output directory if needed
    mkdir -p "$output_dir" || fatal "Failed to create output directory: $output_dir"

    # Determine if version is major.minor or major.minor.patch
    local file_glob
    local version_regex
    local version_desc

    if [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        # Major.minor only (e.g., 6.0, 10.2) - download latest patch
        file_glob="p-isolation-segment-${version}.[0-9]*.*"
        version_regex="^${version}\.[0-9]+.*"
        version_desc="${version}.x (latest patch)"
    else
        # Full version with patch (e.g., 6.0.23, 10.2.6+LTS-T) - download exact version
        # Escape regex special characters in version string (especially + for LTS versions)
        local escaped_version
        escaped_version=$(printf '%s' "$version" | sed 's/[.+^$*?\\[\]{}()|]/\\&/g')
        file_glob="p-isolation-segment-${version}*"
        version_regex="^${escaped_version}$"
        version_desc="$version (exact version)"
    fi

    info "Downloading Isolation Segment tile from Pivnet"
    info "  Version: $version_desc"
    info "  Output: $output_dir"

    # Check if tile already exists
    # Extract base version (strip +LTS-T suffix if present) for filename matching
    local base_version="${version%%+*}"
    local existing_file
    existing_file=$(find "$output_dir" -maxdepth 1 -name "p-isolation-segment-${base_version}*.pivotal" -type f 2>/dev/null | head -1)

    if [[ -n "$existing_file" ]]; then
        warn "Tile already exists: $existing_file"
        local reply
        read -r -p "Re-download and overwrite? [y/N] " reply
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            info "Skipping download. Using existing file."
            info ""
            info "Next step: Install the tile"
            info "  $0 install-tile --tile-path \"$existing_file\""
            return 0
        fi
        info "Overwriting existing tile..."
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN: Would download p-isolation-segment $version_desc to $output_dir"
        return 0
    fi

    # Validate om command
    require_command om

    # Download tile using om
    info "Downloading tile (this may take several minutes)..."

    if om download-product \
        --pivnet-product-slug='p-isolation-segment' \
        --file-glob="$file_glob" \
        --product-version-regex="$version_regex" \
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
# Download Replicator Command
#######################################

download_replicator_usage() {
    cat <<EOF
Usage: $0 download-replicator [OPTIONS]

Download the Replicator tool from Pivotal Network (Pivnet).

The Replicator tool creates multiple isolation segment tiles from a single
base tile. This is required when deploying more than one isolation segment,
as each segment needs its own tile instance with a unique name.

OPTIONS:
    --version VERSION        Release version to download (required)
                            - Use full release version (e.g., 10.2.5+LTS-T, 6.0.23+LTS-T)
                            - Run 'pivnet releases --product-slug=p-isolation-segment' to list
    --output-directory DIR   Download location (default: current directory)
    -h, --help               Show this help message

EXAMPLES:
    # Download replicator for a specific release
    $0 download-replicator --version 10.2.5+LTS-T

    # Download to specific directory
    $0 download-replicator --version 10.2.5+LTS-T --output-directory ~/Downloads

    # List available releases first
    pivnet releases --product-slug='p-isolation-segment'

REQUIREMENTS:
    - PIVNET_TOKEN environment variable must be set
    - pivnet CLI must be installed and logged in

USAGE AFTER DOWNLOAD:
    # Create a replicated tile for a second isolation segment
    ./replicator \
        --name "second-segment" \
        --path /path/to/p-isolation-segment-10.2.5.pivotal \
        --output /path/to/second-segment-10.2.5.pivotal

EOF
}

download_replicator() {
    local version=""
    local output_dir="."

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
                download_replicator_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                download_replicator_usage
                exit 1
                ;;
        esac
    done

    # Validate arguments
    [[ -z "$version" ]] && fatal "Version is required. Use --version VERSION (e.g., 10.2.5+LTS-T)"
    [[ -z "$PIVNET_TOKEN" ]] && fatal "PIVNET_TOKEN environment variable not set"

    # Validate pivnet command
    require_command pivnet
    require_command jq

    # Create output directory if needed
    mkdir -p "$output_dir" || fatal "Failed to create output directory: $output_dir"

    info "Downloading Replicator tool from Pivnet"
    info "  Release version: $version"
    info "  Output: $output_dir"

    # Check if replicator already exists
    local existing_replicator="${output_dir}/replicator"
    if [[ -x "$existing_replicator" ]]; then
        local replicator_version="unknown"
        if [[ -f "${output_dir}/replicator.version" ]]; then
            replicator_version=$(cat "${output_dir}/replicator.version")
        fi
        warn "Replicator already exists: $existing_replicator (version: $replicator_version)"
        local reply
        read -r -p "Re-download and overwrite? [y/N] " reply
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            info "Skipping download. Using existing replicator."
            return 0
        fi
        info "Overwriting existing replicator..."
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN: Would download Replicator for release $version to $output_dir"
        return 0
    fi

    # Ensure pivnet is logged in
    debug "Logging into Pivnet..."
    if ! pivnet login --api-token="$PIVNET_TOKEN" 2>/dev/null; then
        fatal "Failed to login to Pivnet. Check PIVNET_TOKEN."
    fi

    # Verify the release exists before trying to find files
    info "Finding Replicator file ID for release $version..."
    local release_check
    if ! release_check=$(pivnet product-files \
        --product-slug='p-isolation-segment' \
        --release-version="$version" \
        --format='json' 2>&1); then
        if echo "$release_check" | grep -q "release not found"; then
            error "Release '$version' not found"
            info ""
            info "Available releases (showing recent):"
            pivnet releases --product-slug='p-isolation-segment' 2>/dev/null | head -15
            info ""
            info "Use full version string, e.g., --version '10.2.5+LTS-T'"
            fatal "Invalid release version: $version"
        else
            fatal "Pivnet error: $release_check"
        fi
    fi

    local file_id
    file_id=$(echo "$release_check" | jq -r '.[] | select(.name=="Replicator") | .id')

    if [[ -z "$file_id" || "$file_id" == "null" ]]; then
        error "Could not find Replicator file for release $version"
        info ""
        info "Files in this release:"
        echo "$release_check" | jq -r '.[].name'
        fatal "Replicator not found in release $version"
    fi

    debug "Found Replicator file ID: $file_id"

    # Detect platform for binary selection
    local platform
    case "$(uname -s)" in
        Darwin)
            platform="darwin"
            ;;
        Linux)
            platform="linux"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            platform="windows"
            ;;
        *)
            fatal "Unsupported platform: $(uname -s)"
            ;;
    esac
    debug "Detected platform: $platform"

    # Download the replicator
    info "Downloading Replicator (file ID: $file_id)..."
    local temp_dir
    temp_dir=$(mktemp -d)

    cd "$temp_dir" || fatal "Failed to change to temp directory: $temp_dir"

    if ! pivnet download-product-files \
        --product-slug='p-isolation-segment' \
        --release-version="$version" \
        --product-file-id="$file_id" \
        --accept-eula; then
        cd - > /dev/null || true
        rm -rf "$temp_dir"
        fatal "Failed to download Replicator"
    fi

    # Find the downloaded zip file
    local zip_file
    zip_file=$(find . -maxdepth 1 -name "replicator*.zip" -type f 2>/dev/null | head -1)

    if [[ -z "$zip_file" ]]; then
        cd - > /dev/null || true
        rm -rf "$temp_dir"
        fatal "Downloaded file not found or not a ZIP file"
    fi

    info "Extracting $zip_file..."
    if ! unzip -q "$zip_file"; then
        cd - > /dev/null || true
        rm -rf "$temp_dir"
        fatal "Failed to extract replicator ZIP file"
    fi

    # Find the platform-specific binary
    local binary_name="replicator-${platform}"
    [[ "$platform" == "windows" ]] && binary_name="replicator-windows.exe"

    if [[ ! -f "$binary_name" ]]; then
        error "Binary '$binary_name' not found in ZIP archive"
        info "Available files:"
        ls -la
        cd - > /dev/null || true
        rm -rf "$temp_dir"
        fatal "Platform binary not found"
    fi

    # Install the binary
    local target_path="${output_dir}/replicator"
    [[ "$platform" == "windows" ]] && target_path="${output_dir}/replicator.exe"

    cp "$binary_name" "$target_path" || fatal "Failed to copy binary to $target_path"
    chmod +x "$target_path"

    # Extract and save version from zip filename (e.g., replicator-0.18.0.zip -> 0.18.0)
    local replicator_version
    replicator_version=$(echo "$zip_file" | sed -E 's/.*replicator-([0-9]+\.[0-9]+\.[0-9]+)\.zip/\1/')
    if [[ -n "$replicator_version" && "$replicator_version" != "$zip_file" ]]; then
        echo "$replicator_version" > "${output_dir}/replicator.version"
    fi

    # Cleanup
    cd - > /dev/null || true
    rm -rf "$temp_dir"

    success "Installed: $target_path (version: ${replicator_version:-unknown})"
    info ""
    info "Replicator usage example:"
    echo -e "${BLUE}  $target_path \\\\${NC}"
    echo -e "${BLUE}    --name \"second-segment\" \\\\${NC}"
    echo -e "${BLUE}    --path /path/to/p-isolation-segment.pivotal \\\\${NC}"
    echo -e "${BLUE}    --output /path/to/second-segment.pivotal${NC}"
}

#######################################
# Replicate Tile Command
#######################################

replicate_tile_usage() {
    cat <<EOF
Usage: $0 replicate-tile [OPTIONS]

Create a new isolation segment tile using the Replicator tool.

Each isolation segment requires its own tile instance with a unique name.
Use this command to create copies of the base tile for additional segments.

OPTIONS:
    --source PATH        Path to source isolation segment tile (required)
    --name NAME          Name for the new segment (required)
                        - Must be unique across all isolation segments
                        - Permitted: letters, numbers, hyphens, underscores, spaces
    --output PATH        Output path for new tile (default: same directory as source)
    --replicator PATH    Path to replicator binary (default: ./replicator or /tmp/replicator)
    -h, --help           Show this help message

EXAMPLES:
    # Create tiles for small, medium, and large cell segments
    $0 replicate-tile --source ~/Downloads/p-isolation-segment-10.2.5.pivotal --name small-cell
    $0 replicate-tile --source ~/Downloads/p-isolation-segment-10.2.5.pivotal --name medium-cell
    $0 replicate-tile --source ~/Downloads/p-isolation-segment-10.2.5.pivotal --name large-cell

    # Specify custom output location
    $0 replicate-tile --source ~/Downloads/p-isolation-segment-10.2.5.pivotal \\
        --name prod-segment --output /tmp/tiles/prod-segment.pivotal

REQUIREMENTS:
    - Replicator binary must be available (download with: $0 download-replicator)

EOF
}

replicate_tile() {
    local source_tile=""
    local segment_name=""
    local output_path=""
    local replicator_path=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --source)
                source_tile="$2"
                shift 2
                ;;
            --name)
                segment_name="$2"
                shift 2
                ;;
            --output)
                output_path="$2"
                shift 2
                ;;
            --replicator)
                replicator_path="$2"
                shift 2
                ;;
            -h|--help)
                replicate_tile_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                replicate_tile_usage
                exit 1
                ;;
        esac
    done

    # Validate arguments
    [[ -z "$source_tile" ]] && fatal "Source tile is required. Use --source PATH"
    [[ -z "$segment_name" ]] && fatal "Segment name is required. Use --name NAME"
    [[ ! -f "$source_tile" ]] && fatal "Source tile not found: $source_tile"

    # Find replicator binary
    if [[ -z "$replicator_path" ]]; then
        # Try common locations
        if [[ -x "./replicator" ]]; then
            replicator_path="./replicator"
        elif [[ -x "/tmp/replicator" ]]; then
            replicator_path="/tmp/replicator"
        elif command -v replicator &> /dev/null; then
            replicator_path="replicator"
        else
            fatal "Replicator not found. Download it first: $0 download-replicator --version VERSION"
        fi
    fi

    [[ ! -x "$replicator_path" ]] && fatal "Replicator not executable: $replicator_path"

    # Extract version from source filename for output naming
    local source_basename
    source_basename=$(basename "$source_tile")
    local version_part
    version_part=$(echo "$source_basename" | sed -E 's/p-isolation-segment-([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

    # Determine output path
    if [[ -z "$output_path" ]]; then
        # Default to same directory as source
        local source_dir
        source_dir=$(dirname "$source_tile")
        if [[ -n "$version_part" && "$version_part" != "$source_basename" ]]; then
            output_path="${source_dir}/p-isolation-segment-${segment_name}-${version_part}.pivotal"
        else
            output_path="${source_dir}/p-isolation-segment-${segment_name}.pivotal"
        fi
    elif [[ -d "$output_path" ]]; then
        # User provided a directory - construct filename inside it
        if [[ -n "$version_part" && "$version_part" != "$source_basename" ]]; then
            output_path="${output_path}/p-isolation-segment-${segment_name}-${version_part}.pivotal"
        else
            output_path="${output_path}/p-isolation-segment-${segment_name}.pivotal"
        fi
    fi
    # Otherwise use output_path as-is (user provided full filename)

    info "Creating replicated tile"
    info "  Source: $source_tile"
    info "  Segment name: $segment_name"
    info "  Output: $output_path"
    info "  Replicator: $replicator_path"

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN: Would create $output_path from $source_tile"
        return 0
    fi

    # Check if output already exists
    if [[ -f "$output_path" ]]; then
        warn "Output file already exists: $output_path"
        warn "Overwriting..."
    fi

    # Run replicator
    if "$replicator_path" \
        -name "$segment_name" \
        -path "$source_tile" \
        -output "$output_path"; then

        success "Created: $output_path"
        info ""
        info "Next step: Install the tile"
        info "  $0 install-tile --tile-path \"$output_path\""
    else
        fatal "Replicator failed to create tile"
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

    # Get the latest available version from Ops Manager (just uploaded)
    info "Querying available product versions..."
    local available_versions
    available_versions=$(om available-products --format json 2>/dev/null)

    if [[ -z "$available_versions" ]]; then
        warn "Could not query available product versions"
        info "Manually stage the tile: om stage-product --product-name p-isolation-segment --product-version VERSION"
        info "Or use Ops Manager UI: Installation Dashboard → isolation-segment → Stage"
        return 0
    fi

    # Find the most recent p-isolation-segment version (likely the one just uploaded)
    local tile_version
    tile_version=$(echo "$available_versions" | jq -r '.[] | select(.name == "p-isolation-segment") | .version' | head -1)

    if [[ -z "$tile_version" ]]; then
        warn "Could not find p-isolation-segment in available products"
        info "Manually stage the tile: om stage-product --product-name p-isolation-segment --product-version VERSION"
        return 0
    fi

    info "Staging tile version $tile_version..."
    if om stage-product --product-name p-isolation-segment --product-version "$tile_version"; then
        success "Tile staged successfully"
    else
        error "Failed to stage tile version $tile_version"
        info "Try staging manually via Ops Manager UI or:"
        info "  om available-products  # to see all versions"
        info "  om stage-product --product-name p-isolation-segment --product-version VERSION"
        return 1
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

Configure an Isolation Segment tile using om configure-product.

OPTIONS:
    --product NAME       Product name in Ops Manager (required)
                        - For base tile: p-isolation-segment
                        - For replicated tiles: small-cell, medium-cell, etc.
    --vars-file PATH     Path to vars file (required)
                        - Pre-configured files in config/isolation-segment/
    --secrets-file PATH  Path to secrets vars file (optional)
                        - Contains SSL certificates/keys
                        - Auto-detected from config-dir/secrets/ssl-certs.yml
    --config-dir PATH    Config template directory (default: config/isolation-segment)
    --apply              Apply changes after configuration (optional)
    -h, --help           Show this help message

EXAMPLES:
    # Configure using pre-made vars file (secrets auto-detected)
    $0 configure-segment --product p-isolation-segment-small-cell --vars-file config/isolation-segment/small-cell-vars.yml

    # Configure with explicit secrets file
    $0 configure-segment --product p-isolation-segment-small-cell --vars-file config/isolation-segment/small-cell-vars.yml --secrets-file /path/to/secrets.yml

    # Configure and apply changes
    $0 configure-segment --product p-isolation-segment-medium-cell --vars-file config/isolation-segment/medium-cell-vars.yml --apply

    # Configure with custom config directory
    $0 configure-segment --product p-isolation-segment-large-cell --vars-file ./my-vars.yml --config-dir ./my-config

PRE-CONFIGURED VARS FILES:
    config/isolation-segment/small-cell-vars.yml   - 3 diego cells
    config/isolation-segment/medium-cell-vars.yml  - 5 diego cells
    config/isolation-segment/large-cell-vars.yml   - 10 diego cells

SECRETS FILE:
    The script auto-detects secrets from config-dir/secrets/ssl-certs.yml.
    This file should contain SSL certificate/key values:
      networking_poe_ssl_certs_0_certificate: |
        -----BEGIN CERTIFICATE-----
        ...
      networking_poe_ssl_certs_0_privatekey: |
        -----BEGIN RSA PRIVATE KEY-----
        ...

GENERATE VARS FILE:
    # Export existing tile config as starting point
    om staged-config -p p-isolation-segment -c > base-config.yml

EOF
}

configure_segment() {
    local product_name=""
    local vars_file=""
    local secrets_file=""
    local config_dir=""
    local apply_changes=false

    # Default config directory (relative to script location)
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    config_dir="${script_dir}/config/isolation-segment"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --product)
                product_name="$2"
                shift 2
                ;;
            --vars-file)
                vars_file="$2"
                shift 2
                ;;
            --secrets-file)
                secrets_file="$2"
                shift 2
                ;;
            --config-dir)
                config_dir="$2"
                shift 2
                ;;
            --apply)
                apply_changes=true
                shift
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
    [[ -z "$product_name" ]] && fatal "Product name is required. Use --product NAME"
    [[ -z "$vars_file" ]] && fatal "Vars file is required. Use --vars-file PATH"
    [[ ! -f "$vars_file" ]] && fatal "Vars file not found: $vars_file"
    [[ ! -d "$config_dir" ]] && fatal "Config directory not found: $config_dir"

    # Check for required config files
    local product_yml="${config_dir}/product.yml"
    local default_vars="${config_dir}/default-vars.yml"
    local features_dir="${config_dir}/features"

    [[ ! -f "$product_yml" ]] && fatal "Product template not found: $product_yml"
    [[ ! -f "$default_vars" ]] && fatal "Default vars not found: $default_vars"

    # Auto-detect secrets file if not specified
    if [[ -z "$secrets_file" ]]; then
        local default_secrets="${config_dir}/secrets/ssl-certs.yml"
        if [[ -f "$default_secrets" ]]; then
            secrets_file="$default_secrets"
            debug "Auto-detected secrets file: $secrets_file"
        fi
    fi

    # Validate secrets file if specified
    if [[ -n "$secrets_file" && ! -f "$secrets_file" ]]; then
        fatal "Secrets file not found: $secrets_file"
    fi

    info "Configuring Isolation Segment tile"
    info "  Product: $product_name"
    info "  Vars file: $vars_file"
    [[ -n "$secrets_file" ]] && info "  Secrets file: $secrets_file"
    info "  Config dir: $config_dir"

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN: Would configure product $product_name"
        info "Command would be:"
        info "  om configure-product \\"
        info "    --config $product_yml \\"
        info "    --vars-file $default_vars \\"
        info "    --vars-file $vars_file \\"
        [[ -n "$secrets_file" ]] && info "    --vars-file $secrets_file \\"
        info "    --ops-file ${features_dir}/compute_isolation-enabled.yml \\"
        info "    --ops-file ${features_dir}/routing_table_sharding_mode-isolation_segment_only.yml"
        return 0
    fi

    # Validate OM connection
    validate_om_connection

    # Build the om configure-product command
    info "Running om configure-product..."

    # Create a temporary product.yml with the correct product name and job names
    local temp_product_yml
    temp_product_yml=$(mktemp)

    # Extract segment name from product name (e.g., p-isolation-segment-small-cell -> small-cell)
    local segment_name=""
    local segment_name_underscored=""
    if [[ "$product_name" =~ ^p-isolation-segment-(.+)$ ]]; then
        segment_name="${BASH_REMATCH[1]}"
        # Job names use underscores instead of hyphens (e.g., small_cell not small-cell)
        segment_name_underscored="${segment_name//-/_}"
        debug "Detected segment name: $segment_name (job suffix: $segment_name_underscored)"
    fi

    # For replicated tiles, job names have the segment name appended with underscores
    # e.g., isolated_diego_cell_small_cell, isolated_router_small_cell
    if [[ -n "$segment_name_underscored" ]]; then
        sed -e "s/^product-name: .*/product-name: ${product_name}/" \
            -e "s/isolated_diego_cell:/isolated_diego_cell_${segment_name_underscored}:/" \
            -e "s/isolated_router:/isolated_router_${segment_name_underscored}:/" \
            "$product_yml" > "$temp_product_yml"
    else
        sed "s/^product-name: .*/product-name: ${product_name}/" "$product_yml" > "$temp_product_yml"
    fi

    # Build vars file arguments
    local vars_args=("--vars-file" "$default_vars" "--vars-file" "$vars_file")
    if [[ -n "$secrets_file" ]]; then
        vars_args+=("--vars-file" "$secrets_file")
    fi

    if om configure-product \
        --config "$temp_product_yml" \
        "${vars_args[@]}" \
        --ops-file "${features_dir}/compute_isolation-enabled.yml" \
        --ops-file "${features_dir}/routing_table_sharding_mode-isolation_segment_only.yml"; then

        rm -f "$temp_product_yml"
        success "Product $product_name configured successfully"

        if [[ "$apply_changes" == "true" ]]; then
            info "Applying changes..."
            if om apply-changes --product-name "$product_name"; then
                success "Changes applied successfully"
            else
                error "Failed to apply changes"
                info "You can retry with: om apply-changes --product-name $product_name"
                return 1
            fi
        else
            info ""
            info "Next steps:"
            info "  1. Review configuration in Ops Manager UI"
            info "  2. Apply changes: om apply-changes --product-name $product_name"
            info "  3. Register segment: $0 register-segment --name SEGMENT_NAME"
        fi
    else
        rm -f "$temp_product_yml"
        fatal "Failed to configure product $product_name"
    fi
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
    $0 register-segment --name large-cell

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
            download-tile|download-replicator|replicate-tile|install-tile|configure-segment|register-segment|help)
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
        download-replicator)
            download_replicator "$@"
            ;;
        replicate-tile)
            replicate_tile "$@"
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
