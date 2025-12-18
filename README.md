# Shared Isolation Segments for Performance and Density

**Objective:** Use Cloud Foundry isolation segments with shared routing to improve application performance and Diego cell density with minimal operational impact.

## Overview

This guide demonstrates how to leverage isolation segments to:

- **Improve performance** by eliminating noisy neighbors (dedicated Diego cells)
- **Increase density** by deploying larger cells with better bin-packing efficiency
- **Minimize impact** by using shared routing (no network infrastructure changes)
- **Enable gradual migration** with easy rollback capabilities

**Key Benefit:** Compute isolation without network isolation = maximum performance and density gains with minimal operational complexity.

## What's Included

### 📖 Documentation

**[isolation-segments-performance-density.md](./isolation-segments-performance-density.md)**

- Comprehensive implementation guide
- Segment strategy examples (high-density, high-performance, high-memory, high-CPU)
- Gradual migration methodology with zero downtime
- Capacity planning calculations and examples
- Monitoring best practices
- Rollback procedures
- Complete implementation roadmap

### 🔧 Automation Scripts

#### isolation-segment-tile-migration.sh (SUPPORTED - Production)

**[isolation-segment-tile-migration.sh](./isolation-segment-tile-migration.sh)** - **Use this for production deployments**

- Official Isolation Segment tile installation via Ops Manager
- **SUPPORTED by Broadcom** for production use
- Commands: `install-tile`, `configure-segment`, `register-segment`
- Requires: `om` CLI and Ops Manager credentials
- Environment variables: `OM_TARGET`, `OM_USERNAME`, `OM_PASSWORD`

#### isolation-segment-migration.sh (TESTING ONLY)

**[isolation-segment-migration.sh](./isolation-segment-migration.sh)** - **Testing/development only**

- Direct BOSH deployment (bypasses tile management)
- **NOT supported by Broadcom** - for testing only
- Commands: `create-segment` (BOSH), `migrate`, `monitor`, `rollback`, `validate`
- Faster for quick testing but lacks production support
- Requires: BOSH Director access
- Environment variables: `BOSH_ENVIRONMENT`, `BOSH_CLIENT`, `BOSH_CLIENT_SECRET`

## Quick Start

### 1. Review the Strategy

Read the complete implementation guide:

```bash
less isolation-segments-performance-density.md
```

### 2. Validate Prerequisites

```bash
# Check required tools
cf --version
bosh --version  # If managing BOSH directly
jq --version

# Verify CF connection
cf api
cf target

# View script help
./isolation-segment-migration.sh --help
```

### 3. Create an Isolation Segment

**Production (Tile-based - SUPPORTED):**
```bash
# Install tile
./isolation-segment-tile-migration.sh install-tile \
  --tile-path ~/Downloads/isolation-segment-6.0.x.pivotal

# Configure via Ops Manager UI or:
./isolation-segment-tile-migration.sh configure-segment \
  --name high-density \
  --cell-count 120

# Apply changes in Ops Manager, then register
./isolation-segment-tile-migration.sh register-segment --name high-density
```

**Testing only (BOSH direct - NOT SUPPORTED):**
```bash
# Quick test deployment
./isolation-segment-migration.sh create-segment \
  --name test-segment \
  --cell-size 4/32 \
  --count 10 \
  --register
```

### 4. Migrate Applications (Dry Run First)

```bash
# Preview migration without executing
./isolation-segment-migration.sh migrate \
  --org production-org \
  --space prod-space \
  --segment high-density \
  --entitle \
  --dry-run

# Execute migration in batches
./isolation-segment-migration.sh migrate \
  --org production-org \
  --space prod-space \
  --segment high-density \
  --entitle \
  --batch-size 10 \
  --delay 30
```

### 5. Monitor Segment Performance

```bash
# One-time capacity check
./isolation-segment-migration.sh monitor --segment high-density

# Real-time monitoring (refresh every 10 seconds)
./isolation-segment-migration.sh monitor --segment high-density --watch 10

# Export metrics as JSON
./isolation-segment-migration.sh monitor --segment high-density --output json
```

### 6. Rollback if Needed

```bash
# Rollback entire space to shared segment
./isolation-segment-migration.sh rollback \
  --org production-org \
  --space prod-space

# Rollback specific apps only
./isolation-segment-migration.sh rollback \
  --org production-org \
  --space prod-space \
  --apps app1,app2,app3
```

## Key Concepts

### Shared Routing (Default - Recommended)

**What it means:**

- TAS Gorouters handle traffic for **both** shared segment and isolation segment apps
- Apps keep their **exact same routes/domains** (no DNS changes)
- Zero changes to load balancers, SSL certificates, or network topology

**Network path:**

```
Client → Existing LB → TAS Gorouter → App (Shared or Isolation Segment Diego Cell)
                                            ↑
                                       Only this changes
```

**Configuration:**

- In TAS tile **Networking** pane: `Accept requests for all isolation segments`
- No dedicated Gorouters needed
- Lower operational overhead

### Segment Types

| Segment Type | Cell Size | Best For |
|--------------|-----------|----------|
| **High-Density** | 8/64 (8 vCPU, 64GB) | Microservices, web apps, background workers |
| **High-Performance** | 4/32 (4 vCPU, 32GB) | Production apps, strict SLAs, revenue-critical |
| **High-Memory** | 4/128 (4 vCPU, 128GB) | Analytics, data processing, large Java apps |
| **High-CPU** | 8/32 (8 vCPU, 32GB) | Image/video processing, ML inference, compute-heavy |

### Migration Strategy

1. **Keep existing workloads untouched** - All apps stay on shared segment initially
2. **Deploy optimized segments** - Add new Diego cells with specific configurations
3. **Test thoroughly** - Pilot with non-critical apps first
4. **Migrate in waves** - Gradual rollout (25% per month) with monitoring
5. **Monitor continuously** - Track performance, capacity, and app health
6. **Easy rollback** - Simple space reassignment if issues occur

## Expected Benefits

**Performance Improvements:**

- ✅ Predictable performance (no noisy neighbors)
- ✅ Reduced resource contention
- ✅ Optimized cell configurations for workload types
- ✅ Fewer CPU throttling events

**Density Improvements:**

- ✅ 10-50% reduction in VM count (depending on cell sizing)
- ✅ Better bin-packing efficiency with larger cells
- ✅ Higher resource utilization
- ✅ Reduced infrastructure overhead

**Operational Impact:**

- ✅ Zero downtime during deployment
- ✅ Zero changes to existing workloads
- ✅ Zero route/DNS/certificate changes
- ✅ Gradual, controlled migration with easy rollback

## Official Documentation

### Broadcom TechDocs - EAR 6.0 (Current)

**Installation and Configuration:**

- [Installing Isolation Segment (EAR 6.0)](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/6-0/eart/installing-pcf-is.html)
- [Managing Isolation Segments](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-platform-for-cloud-foundry/6-0/tpcf/isolation-segments.html)
- [Routing for Isolation Segments](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/6-0/eart/routing-is.html)

**Capacity Planning:**

- [Diego Cell Sizing and Capacity](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/6-0/eart/capacity-planning.html)
- [Scaling Cloud Foundry](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-platform-for-cloud-foundry/6-0/tpcf/scaling-ert-components.html)

**Operations:**

- [Using the Cloud Foundry Command Line Interface (CF CLI)](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-platform-for-cloud-foundry/6-0/tpcf/cf-cli.html)
- [BOSH Operations](https://bosh.io/docs/)

### Broadcom TechDocs - EAR 10.3 (Latest)

**Installation and Configuration:**

- [Installing Isolation Segment (EAR 10.3)](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/10-3/eart/installing-pcf-is.html)
- [Managing Isolation Segments](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-platform-for-cloud-foundry/10-3/tpcf/isolation-segments.html)
- [Routing for Isolation Segments](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/10-3/eart/routing-is.html)

**Capacity Planning:**

- [Diego Cell Sizing and Capacity](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/10-3/eart/capacity-planning.html)
- [Scaling Cloud Foundry](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-platform-for-cloud-foundry/10-3/tpcf/scaling-ert-components.html)

### Cloud Foundry Documentation

**Isolation Segments:**

- [Cloud Foundry Isolation Segments](https://docs.cloudfoundry.org/adminguide/isolation-segments.html)
- [CF CLI Isolation Segment Commands](https://cli.cloudfoundry.org/en-US/v8/)

**Diego Architecture:**

- [Diego Components and Architecture](https://docs.cloudfoundry.org/concepts/diego/diego-architecture.html)
- [Diego Cell Rep](https://docs.cloudfoundry.org/concepts/architecture/#nsync-bbs-and-cell-reps)

## Environment Variables

The script supports environment variable overrides for sensitive data:

```bash
export CF_API="https://api.sys.example.com"
export CF_USERNAME="admin"
export CF_PASSWORD="your-password"

export BOSH_ENVIRONMENT="https://bosh.example.com:25555"
export BOSH_CLIENT="admin"
export BOSH_CLIENT_SECRET="your-bosh-password"
export BOSH_CA_CERT="/path/to/bosh-ca.crt"

export BATCH_SIZE=10              # Apps per batch (default: 10)
export MIGRATION_DELAY=30         # Seconds between app restarts (default: 30)
export DRY_RUN=false             # Preview mode (default: false)
export VERBOSE=true              # Debug logging (default: false)
export LOG_FILE=/tmp/migration.log  # Log file path
```

## Troubleshooting

### Apps Not Deploying to Expected Segment

```bash
# Check space assignment
cf space SPACE-NAME

# Check org entitlement
cf org ORG-NAME

# Check app segment
cf app APP-NAME

# Fix: Ensure org is entitled and space is assigned
cf enable-org-isolation ORG-NAME SEGMENT-NAME
cf set-space-isolation-segment SPACE-NAME SEGMENT-NAME
cf restart APP-NAME
```

### Validate Segment Configuration

```bash
# Use built-in validation
./isolation-segment-migration.sh validate --segment SEGMENT-NAME

# Manual checks
cf isolation-segments
bosh -e ENV -d DEPLOYMENT vms
bosh -e ENV -d DEPLOYMENT ssh diego_cell/0 -c "curl -s localhost:1800/state | jq .AvailableResources"
```

### Monitor Segment Capacity

```bash
# Real-time monitoring
./isolation-segment-migration.sh monitor --segment SEGMENT-NAME --watch 10

# Check Diego cell utilization
bosh -e ENV -d DEPLOYMENT ssh diego_cell/0 \
  -c "curl -s localhost:1800/state | jq .AvailableResources.MemoryMB"
```

## Support

For issues or questions:

- Review the comprehensive guide: `isolation-segments-performance-density.md`
- Check script help: `./isolation-segment-migration.sh COMMAND --help`
- Consult [Broadcom Support Portal](https://support.broadcom.com/)
- Reference [Cloud Foundry Community](https://www.cloudfoundry.org/community/)

## License

This guide and automation are provided as-is for educational and operational purposes.
