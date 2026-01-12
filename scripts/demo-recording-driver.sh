#!/usr/bin/env bash
# ABOUTME: Interactive demo recording driver script
# ABOUTME: Displays commands one at a time for manual execution during recording

set -uo pipefail

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

STEP=0

show_command() {
    local cmd="$1"
    local note="${2:-}"
    ((STEP++))
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Step $STEP${NC}"
    if [[ -n "$note" ]]; then
        echo -e "${YELLOW}$note${NC}"
    fi
    echo ""
    echo -e "${BLUE}$cmd${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

scene() {
    local title="$1"
    echo ""
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  $title${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════════╝${NC}"
}

marker() {
    local msg="$1"
    echo ""
    echo -e "${YELLOW}▶▶▶ $msg${NC}"
    echo ""
}

wait_for_enter() {
    echo -e "${CYAN}Press ENTER for next command (q to quit, s to skip scene)...${NC}"
    read -r input || input=""
    if [[ "$input" == "q" ]]; then
        echo "Exiting..."
        exit 0
    elif [[ "$input" == "s" ]]; then
        return 1
    fi
    return 0
}

# ============================================================================
# ACT 1: Platform Operator Experience
# ============================================================================

act1_scene1() {
    scene "Scene 1.1: Tile Acquisition"

    show_command './scripts/isolation-segment-tile-migration.sh replicate-tile \
  --source ~/Downloads/p-isolation-segment-10.2.5-build.2.pivotal \
  --name large-cell \
  --output ~/Downloads' "Create the large-cell replicated tile"
    echo ""
    echo -e "${YELLOW}Under the hood, this runs:${NC}"
    echo -e "${BLUE}/tmp/replicator \\
  --name large-cell \\
  --path ~/Downloads/p-isolation-segment-10.2.5-build.2.pivotal \\
  --output ~/Downloads/p-isolation-segment-large-cell-10.2.5.pivotal${NC}"
    echo ""
    wait_for_enter || return

    show_command 'ls -lh ~/Downloads/p-isolation-segment-large-cell-10.2.5.pivotal' "Verify tile was created"
    wait_for_enter || return
}

act1_scene2() {
    scene "Scene 1.2: Ops Manager Installation"

    show_command 'om upload-product --product ~/Downloads/p-isolation-segment-large-cell-10.2.5.pivotal' "Upload tile to Ops Manager"
    wait_for_enter || return

    show_command 'om stage-product \
  --product-name p-isolation-segment-large-cell \
  --product-version 10.2.5' "Stage the tile"
    wait_for_enter || return

    marker "[BROWSER] Configure tile in Ops Manager UI"
    marker "- Assign AZs and Networks"
    marker "- Isolated Diego Cells: 1 cell"
    marker "- Networking: 0 routers (shared routing)"
    wait_for_enter || return

    marker "[BROWSER] Review Pending Changes → Apply Changes"
    marker "[CUT] Stop recording - wait for Apply Changes (~10-15 min)"
    wait_for_enter || return

    marker "[RESUME] Show successful deployment in browser"
    wait_for_enter || return
}

act1_scene3() {
    scene "Scene 1.3: Segment Registration"

    show_command 'cf create-isolation-segment large-cell' "Register segment in Cloud Controller"
    wait_for_enter || return

    show_command 'cf enable-org-isolation demo-org large-cell' "Enable for organization"
    wait_for_enter || return

    show_command 'cf create-space iso-validation -o demo-org' "Create validation space for operator testing"
    wait_for_enter || return

    show_command 'cf set-space-isolation-segment iso-validation large-cell' "Assign validation space to segment"
    wait_for_enter || return

    show_command 'cf isolation-segments' "Verify segment is registered"
    wait_for_enter || return

    show_command 'cf space iso-validation' "Verify space assignment"
    wait_for_enter || return
}

act1_scene4() {
    scene "Scene 1.4: Operator Validation"

    show_command 'cf target -o demo-org -s iso-validation' "Target the validation space"
    wait_for_enter || return

    show_command 'cd apps/cf-env && cf push cf-env-test -m 64M -k 128M && cd ../..' "Deploy test application"
    wait_for_enter || return

    show_command 'cf app cf-env-test' "Verify app is running"
    wait_for_enter || return

    marker "[BROWSER] Open app URL to show it responds"
    wait_for_enter || return

    show_command 'cf space iso-validation' "Verify space shows isolation segment"
    wait_for_enter || return

    show_command 'echo "App running on: $(curl -s "https://$(cf app cf-env-test | grep routes | awk '"'"'{print $2}'"'"')/env" | grep CF_INSTANCE_IP | cut -d= -f2)"
echo "Large-cell Diego: $(bosh -d p-isolation-segment-large-cell-2ce92833ad1ce8f6e40a instances --json 2>/dev/null | jq -r '"'"'.Tables[0].Rows[0].ips'"'"')"' "Verify app running on isolated cell"
    wait_for_enter || return

    show_command 'echo "Isolation segment '"'"'large-cell'"'"' validated and ready for tenant workloads"' "Declare segment ready"
    wait_for_enter || return
}

# ============================================================================
# ACT 2: App Developer Experience
# ============================================================================

act2_scene1() {
    scene "Scene 2.1: Before State"

    show_command 'cf target -o demo-org -s dev-space' "Developer targets their space"
    wait_for_enter || return

    show_command 'cf apps' "List apps in space"
    wait_for_enter || return

    show_command 'cf app spring-music' "Show Spring Music details"
    wait_for_enter || return

    show_command 'cf space dev-space' "Check current space config (no isolation segment)"
    wait_for_enter || return

    marker "[BROWSER] Open Spring Music URL to show it works"
    wait_for_enter || return
}

act2_scene2() {
    scene "Scene 2.2: Migration Notice"

    show_command 'cat << '"'"'EOF'"'"'
================================================================================
PLATFORM NOTIFICATION

Subject: Isolation Segment Migration - Action Required

Your space '"'"'dev-space'"'"' has been assigned to isolation segment '"'"'large-cell'"'"'
for improved resource allocation and workload isolation.

ACTION REQUIRED:
  Please restage your applications by Friday, January 17, 2026 to
  complete the migration.

  Command: cf restage <app-name>

Questions? Contact platform-team@example.com
================================================================================
EOF' "Display migration notification"
    wait_for_enter || return
}

act2_scene3() {
    scene "Scene 2.3: Developer Performs Restage"

    show_command 'cf set-space-isolation-segment dev-space large-cell' "Platform operator assigns space to segment"
    wait_for_enter || return

    show_command 'cf space dev-space' "Developer verifies space assignment"
    wait_for_enter || return

    show_command 'cf restage spring-music' "Developer restages application (THE ONLY ACTION NEEDED)"
    wait_for_enter || return
}

act2_scene4() {
    scene "Scene 2.4: Developer Verification"

    show_command 'cf space dev-space' "Confirm space shows isolation segment"
    wait_for_enter || return

    show_command 'cf app spring-music' "Check app status"
    wait_for_enter || return

    marker "[BROWSER] Refresh Spring Music URL, click around"
    wait_for_enter || return

    show_command 'cf app spring-music | grep -E "routes|memory|buildpack"' "Highlight zero changes required"
    wait_for_enter || return

    show_command 'echo "App running on: $(cf curl /v3/apps/$(cf app spring-music --guid)/processes/web/stats 2>/dev/null | jq -r '"'"'.resources[0].host'"'"')"
echo "Large-cell Diego: $(bosh -d p-isolation-segment-large-cell-2ce92833ad1ce8f6e40a instances --json 2>/dev/null | jq -r '"'"'.Tables[0].Rows[0].ips'"'"')"' "Verify app running on isolated cell"
    wait_for_enter || return

    show_command 'echo "✓ Confirmed: spring-music is running on the large-cell isolation segment"' "Confirm isolation"
    wait_for_enter || return

    show_command 'echo ""
echo "=== Migration Complete ==="
echo "App: spring-music"
echo "Isolation Segment: large-cell"
echo "Developer action: cf restage (1 command)"
echo "Changes to app code: NONE"
echo "Changes to routes: NONE"
echo "Changes to deployment process: NONE"' "Closing summary"
    wait_for_enter || return

    echo ""
    echo -e "${GREEN}🎬 END OF DEMO - Stop Recording${NC}"
    echo ""
}

# ============================================================================
# Main Menu
# ============================================================================

cleanup_demo() {
    echo ""
    echo -e "${YELLOW}Cleaning up demo environment...${NC}"
    echo ""

    echo "Cleaning up CF resources..."
    cf target -o demo-org -s dev-space 2>/dev/null || true
    cf delete cf-env-test -f 2>/dev/null || true
    cf reset-space-isolation-segment dev-space 2>/dev/null || true
    cf reset-space-isolation-segment iso-validation 2>/dev/null || true
    cf delete-space iso-validation -o demo-org -f 2>/dev/null || true
    cf disable-org-isolation demo-org large-cell 2>/dev/null || true
    cf delete-isolation-segment large-cell -f 2>/dev/null || true
    rm -f ~/Downloads/p-isolation-segment-large-cell-10.2.5.pivotal

    echo ""
    echo "Cleaning up Ops Manager..."
    if om staged-products 2>/dev/null | grep -q "p-isolation-segment-large-cell"; then
        echo "Unstaging large-cell tile from Ops Manager..."
        om unstage-product --product-name p-isolation-segment-large-cell 2>/dev/null || true
    fi

    if om deployed-products 2>/dev/null | grep -q "p-isolation-segment-large-cell"; then
        echo "Deleting large-cell tile from Ops Manager..."
        om delete-product --product-name p-isolation-segment-large-cell --product-version 10.2.5 2>/dev/null || true
        echo ""
        echo -e "${YELLOW}Tile marked for deletion. Running Apply Changes...${NC}"
        echo -e "${YELLOW}This will take 10-15 minutes. Press Ctrl+C to skip.${NC}"
        echo ""
        read -rp "Press ENTER to start Apply Changes (or Ctrl+C to skip): "
        om apply-changes --product-name p-isolation-segment-large-cell 2>/dev/null || true
    fi

    echo ""
    echo -e "${GREEN}✓ Demo environment reset${NC}"
    echo ""
}

main_menu() {
    # Handle --cleanup flag
    if [[ "${1:-}" == "--cleanup" ]]; then
        cleanup_demo
        exit 0
    fi

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       Isolation Segments Demo Recording Driver                         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Select starting point:"
    echo ""
    echo "  ACT 1: Platform Operator Experience"
    echo "    1) Scene 1.1: Tile Acquisition"
    echo "    2) Scene 1.2: Ops Manager Installation"
    echo "    3) Scene 1.3: Segment Registration"
    echo "    4) Scene 1.4: Operator Validation"
    echo ""
    echo "  ACT 2: App Developer Experience"
    echo "    5) Scene 2.1: Before State"
    echo "    6) Scene 2.2: Migration Notice"
    echo "    7) Scene 2.3: Developer Performs Restage"
    echo "    8) Scene 2.4: Developer Verification"
    echo ""
    echo "    a) Run ALL scenes from beginning"
    echo "    q) Quit"
    echo ""
    read -rp "Choice: " choice

    case $choice in
        1) act1_scene1; act1_scene2; act1_scene3; act1_scene4; act2_scene1; act2_scene2; act2_scene3; act2_scene4 ;;
        2) act1_scene2; act1_scene3; act1_scene4; act2_scene1; act2_scene2; act2_scene3; act2_scene4 ;;
        3) act1_scene3; act1_scene4; act2_scene1; act2_scene2; act2_scene3; act2_scene4 ;;
        4) act1_scene4; act2_scene1; act2_scene2; act2_scene3; act2_scene4 ;;
        5) act2_scene1; act2_scene2; act2_scene3; act2_scene4 ;;
        6) act2_scene2; act2_scene3; act2_scene4 ;;
        7) act2_scene3; act2_scene4 ;;
        8) act2_scene4 ;;
        a|A) act1_scene1; act1_scene2; act1_scene3; act1_scene4; act2_scene1; act2_scene2; act2_scene3; act2_scene4 ;;
        q|Q) exit 0 ;;
        *) echo "Invalid choice"; main_menu ;;
    esac
}

main_menu "$@"
