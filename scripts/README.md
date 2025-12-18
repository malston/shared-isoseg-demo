# Demo Scripts

This directory contains demo and utility scripts for Cloud Foundry / TAS / EAR operations.

## demo-isolation-segment-migration.sh

Interactive demo script showing zero-impact migration from shared Diego cells to isolated Diego cells.

### Quick Start

```bash
# Interactive mode (default)
./demo-isolation-segment-migration.sh

# Automated mode with cleanup
./demo-isolation-segment-migration.sh --automated --cleanup
```

### Prerequisites

- CF CLI v7+ (v8+ recommended)
- BOSH CLI v7+ (optional, can skip with `--skip-bosh`)
- jq (JSON processor)
- Active CF API connection (`cf login`)
- Isolation segment tile deployed with Diego cells

### Features

- **Two operating modes:**
  - Interactive: Pauses between steps for live presentations
  - Automated: Runs end-to-end for CI/CD pipelines

- **4-layer verification:**
  1. CF CLI isolation segment field
  2. BOSH physical placement (deployment, instance group, cell IP)
  3. Diego cell capacity metrics
  4. App environment variables

- **Small Footprint TAS support:**
  - Auto-detects `compute` vs `diego_cell` instance groups
  - Handles two separate BOSH deployments

- **Safe cleanup:**
  - Prompts before deleting resources
  - Can preserve environment for exploration

### Usage

```
./demo-isolation-segment-migration.sh [OPTIONS]

OPTIONS:
  --automated              Run in automated mode (no pauses)
  --interactive            Run in interactive mode with pauses (default)
  --segment NAME           Isolation segment name (default: shared-demo)
  --org NAME               Org name (default: shared-isoseg-demo)
  --space NAME             Space name (default: dev)
  --app NAME               App name (default: spring-music)
  --cleanup                Cleanup at end without asking
  --no-cleanup             Skip cleanup at end
  --skip-bosh              Skip BOSH verification (CF CLI only)
  --verbose                Enable verbose output
  -h, --help               Show this help message
  -v, --version            Show version
```

### Environment Variables

```bash
export DEMO_MODE="automated"           # or "interactive"
export DEMO_SEGMENT="shared-demo"
export DEMO_ORG="shared-isoseg-demo"
export DEMO_SPACE="dev"
export DEMO_APP_NAME="spring-music"
export DEMO_CLEANUP="true"             # or "false", "ask", "full"
export DEMO_SKIP_BOSH="false"
export VERBOSE="true"
```

### Examples

**Live Presentation:**
```bash
./demo-isolation-segment-migration.sh --interactive
```

**CI/CD Pipeline:**
```bash
./demo-isolation-segment-migration.sh --automated --cleanup
```

**Custom Segment:**
```bash
./demo-isolation-segment-migration.sh --segment high-density --org prod-demo
```

**Skip BOSH Verification:**
```bash
./demo-isolation-segment-migration.sh --skip-bosh
```

### What It Does

1. **Prerequisites & Setup**
   - Validates CF/BOSH CLI tools
   - Creates demo org and space
   - Verifies isolation segment exists

2. **Deploy App (BEFORE)**
   - Pushes Spring Music to shared Diego cells
   - Captures BEFORE state (4 verification methods)

3. **Enable Isolation Segment**
   - Entitles org to segment
   - Assigns space to segment
   - Restarts app (triggers migration)

4. **Capture AFTER State**
   - Shows app on isolated Diego cells
   - Displays side-by-side comparison

5. **Cleanup** (optional)
   - Deletes app, space, org
   - Cleans up temp files

### Output

**Interactive Mode:**
- Colorful, formatted output
- Pauses between major steps
- Side-by-side comparison table
- Visual indicators (✓, ✨, emojis)

**Automated Mode:**
- Timestamped log output
- Compact verification results
- Exit code 0 on success

### Troubleshooting

**"Isolation segment has no Diego cells"**
- Deploy Diego cells via Ops Manager isolation segment tile first

**"Cannot connect to BOSH"**
- Use `--skip-bosh` to skip BOSH verification
- Relies on CF CLI verification only

**"App push failed"**
- Check buildpack availability
- Verify space quota has capacity
- Review `cf logs` output

### State File

The script saves verification state to `/tmp/demo-state-{timestamp}.json`:

```json
{
  "before": {
    "cf_cli": {...},
    "bosh": {...},
    "capacity": {...},
    "app_env": {...}
  },
  "after": {
    "cf_cli": {...},
    "bosh": {...},
    "capacity": {...},
    "app_env": {...}
  }
}
```

This allows post-demo analysis and programmatic comparison.

### See Also

- Design document: `docs/plans/2025-12-18-demo-isolation-segment-migration.md`
- Implementation plan: `docs/plans/2025-12-18-demo-script-implementation.md`
- Shared isolation segments guide: `~/workspace/shared-isoseg-demo/README.md`
