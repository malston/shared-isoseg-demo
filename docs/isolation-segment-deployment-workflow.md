# Isolation Segment Deployment Workflow

## ABOUTME: Step-by-step guide for deploying multiple isolation segments using the Replicator tool
## ABOUTME: Covers tile replication, installation, configuration, and registration with troubleshooting

This guide documents the complete workflow for deploying multiple isolation segments in TAS/Cloud Foundry using the official Isolation Segment tile and Replicator tool.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Workflow Summary](#workflow-summary)
4. [Step 1: Download the Base Tile](#step-1-download-the-base-tile)
5. [Step 2: Download the Replicator Tool](#step-2-download-the-replicator-tool)
6. [Step 3: Replicate Tiles for Each Segment](#step-3-replicate-tiles-for-each-segment)
7. [Step 4: Upload and Stage Tiles](#step-4-upload-and-stage-tiles)
8. [Step 5: Configure Each Segment](#step-5-configure-each-segment)
9. [Step 6: Deploy via Ops Manager](#step-6-deploy-via-ops-manager)
10. [Step 7: Register Segments in Cloud Controller](#step-7-register-segments-in-cloud-controller)
11. [Quirks and Troubleshooting](#quirks-and-troubleshooting)
12. [Configuration Reference](#configuration-reference)

---

## Overview

### Why Multiple Isolation Segments?

Each isolation segment in Cloud Foundry requires its own tile instance in Ops Manager. The Replicator tool creates uniquely-named tile copies from a single base tile, allowing you to:

- Deploy segments with different cell sizes (small-cell, medium-cell, large-cell)
- Isolate workloads by team, environment, or security requirements
- Configure different resource allocations per segment

### Architecture

```text
Base Tile: p-isolation-segment-10.2.5.pivotal
    │
    ├── Replicator → small-cell-10.2.5.pivotal  → p-isolation-segment-small-cell
    ├── Replicator → medium-cell-10.2.5.pivotal → p-isolation-segment-medium-cell
    └── Replicator → large-cell-10.2.5.pivotal  → p-isolation-segment-large-cell
```

**Key Naming Convention:** The Replicator prefixes tile names with `p-isolation-segment-`. A segment named `small-cell` becomes product `p-isolation-segment-small-cell`.

---

## Prerequisites

### Required Tools

| Tool | Purpose | Installation |
|------|---------|--------------|
| `om` | Ops Manager CLI | [pivotal.io/om](https://github.com/pivotal-cf/om) |
| `pivnet` | Pivotal Network CLI | [pivotal.io/pivnet-cli](https://github.com/pivotal-cf/pivnet-cli) |
| `cf` | Cloud Foundry CLI | [cloudfoundry.org/cf-cli](https://docs.cloudfoundry.org/cf-cli/) |
| `jq` | JSON processor | `brew install jq` or `apt install jq` |

### Environment Variables

```bash
# Ops Manager credentials
export OM_TARGET="https://opsman.example.com"
export OM_USERNAME="admin"
export OM_PASSWORD="your-password"
export OM_SKIP_SSL_VALIDATION=true  # If using self-signed certs

# Pivotal Network token
export PIVNET_TOKEN="your-pivnet-refresh-token"

# Cloud Foundry credentials (for segment registration)
export CF_API="https://api.sys.example.com"
export CF_USERNAME="admin"
export CF_PASSWORD="your-cf-password"
```

### Network Requirements

- Access to Pivotal Network (network.tanzu.vmware.com)
- Access to Ops Manager UI and API
- Access to Cloud Foundry API

---

## Workflow Summary

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ISOLATION SEGMENT DEPLOYMENT WORKFLOW                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. Download base tile from Pivnet                                          │
│     └─ pivnet download-product-files ...                                    │
│                                                                             │
│  2. Download Replicator tool from Pivnet                                    │
│     └─ ./isolation-segment-tile-migration.sh download-replicator ...        │
│                                                                             │
│  3. Replicate tiles for each segment                                        │
│     └─ ./replicator -name small-cell -path base.pivotal -output out.pivotal │
│                                                                             │
│  4. Upload and stage each tile in Ops Manager                               │
│     └─ om upload-product && om stage-product                                │
│                                                                             │
│  5. Configure each segment (properties + resources)                         │
│     └─ om configure-product --config config.yml                             │
│                                                                             │
│  6. Deploy via Ops Manager                                                  │
│     └─ om apply-changes (or via UI)                                         │
│                                                                             │
│  7. Register segments in Cloud Controller                                   │
│     └─ cf create-isolation-segment                                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 1: Download the Base Tile

### Option A: Using Pivnet CLI

```bash
# Login to Pivnet
pivnet login --api-token="$PIVNET_TOKEN"

# List available releases
pivnet releases --product-slug='p-isolation-segment'

# Download a specific version
pivnet download-product-files \
    --product-slug='p-isolation-segment' \
    --release-version='10.2.5+LTS-T' \
    --glob='p-isolation-segment-*.pivotal' \
    --download-dir=~/Downloads \
    --accept-eula
```

### Option B: Using the Migration Script

```bash
./scripts/isolation-segment-tile-migration.sh download-tile \
    --version 10.2 \
    --output-directory ~/Downloads
```

### Option C: Manual Download

Download from [Broadcom Support Portal](https://support.broadcom.com/group/ecx/productdownloads?subfamily=Isolation%20Segmentation%20for%20VMware%20Tanzu%20Platform)

---

## Step 2: Download the Replicator Tool

The Replicator is included with each Isolation Segment release as a ZIP file containing binaries for Linux, macOS, and Windows.

### Using the Migration Script

```bash
./scripts/isolation-segment-tile-migration.sh download-replicator \
    --version '10.2.5+LTS-T' \
    --output-directory /tmp

# Verify installation
/tmp/replicator --help
```

### Manual Download

```bash
# Find the Replicator file ID
pivnet product-files \
    --product-slug='p-isolation-segment' \
    --release-version='10.2.5+LTS-T' \
    --format='json' | jq '.[] | select(.name=="Replicator")'

# Download by file ID
pivnet download-product-files \
    --product-slug='p-isolation-segment' \
    --release-version='10.2.5+LTS-T' \
    --product-file-id=<FILE_ID> \
    --accept-eula

# Extract and install
unzip replicator-*.zip
chmod +x replicator-darwin  # or replicator-linux
mv replicator-darwin /tmp/replicator
```

---

## Step 3: Replicate Tiles for Each Segment

Create a separate tile for each isolation segment you want to deploy.

### Example: Three Segments (Small, Medium, Large)

```bash
BASE_TILE=~/Downloads/p-isolation-segment-10.2.5-build.2.pivotal
OUTPUT_DIR=~/Downloads

# Create small-cell segment tile
/tmp/replicator \
    -name small-cell \
    -path "$BASE_TILE" \
    -output "${OUTPUT_DIR}/small-cell-10.2.5.pivotal"

# Create medium-cell segment tile
/tmp/replicator \
    -name medium-cell \
    -path "$BASE_TILE" \
    -output "${OUTPUT_DIR}/medium-cell-10.2.5.pivotal"

# Create large-cell segment tile
/tmp/replicator \
    -name large-cell \
    -path "$BASE_TILE" \
    -output "${OUTPUT_DIR}/large-cell-10.2.5.pivotal"
```

### Verify Tile Names

After replication, the tiles will have these product names:

| Segment Name | Tile Filename | Product Name in Ops Manager |
|--------------|---------------|------------------------------|
| small-cell | small-cell-10.2.5.pivotal | `p-isolation-segment-small-cell` |
| medium-cell | medium-cell-10.2.5.pivotal | `p-isolation-segment-medium-cell` |
| large-cell | large-cell-10.2.5.pivotal | `p-isolation-segment-large-cell` |

---

## Step 4: Upload and Stage Tiles

### Upload Each Tile

```bash
# Upload small-cell tile
om upload-product --product ~/Downloads/small-cell-10.2.5.pivotal

# Upload medium-cell tile
om upload-product --product ~/Downloads/medium-cell-10.2.5.pivotal

# Upload large-cell tile
om upload-product --product ~/Downloads/large-cell-10.2.5.pivotal
```

### Stage Each Tile

```bash
# Check available products
om available-products --format json | jq '.[] | select(.name | contains("isolation"))'

# Stage each product with correct version
om stage-product --product-name p-isolation-segment-small-cell --product-version 10.2.5
om stage-product --product-name p-isolation-segment-medium-cell --product-version 10.2.5
om stage-product --product-name p-isolation-segment-large-cell --product-version 10.2.5
```

### Verify Staging

```bash
# List staged products
om staged-products --format json | jq '.[] | select(.name | contains("isolation"))'
```

---

## Step 5: Configure Each Segment

### Understanding Configuration Structure

Each isolation segment tile requires three types of configuration:

1. **Product Properties** - Segment name, routing mode, SSL certificates, etc.
2. **Network Properties** - Network assignment and availability zones
3. **Resource Config** - Diego cell count, instance types, router settings

### Important: Job Naming Convention

**Replicated tiles use suffixed job names.** For a segment named `small-cell`:

| Base Tile Job Name | Replicated Tile Job Name |
|--------------------|--------------------------|
| `isolated_diego_cell` | `isolated_diego_cell_small_cell` |
| `isolated_router` | `isolated_router_small_cell` |

**Note:** Hyphens in segment names are converted to underscores in job names.

### Configuration Files

Create configuration files for each segment. See [Configuration Reference](#configuration-reference) for full examples.

**Minimal configuration for small-cell segment:**

```yaml
# /tmp/small-cell-config.yml
product-name: p-isolation-segment-small-cell
product-properties:
  .properties.compute_isolation:
    selected_option: enabled
    value: enabled
  .properties.compute_isolation.enabled.isolation_segment_name:
    value: small-cell
  .properties.routing_table_sharding_mode:
    selected_option: isolation_segment_only
    value: isolation_segment_only
  .properties.networking_poe_ssl_certs:
    value:
    - certificate:
        cert_pem: |
          -----BEGIN CERTIFICATE-----
          ... your certificate ...
          -----END CERTIFICATE-----
        private_key_pem: |
          -----BEGIN RSA PRIVATE KEY-----
          ... your private key ...
          -----END RSA PRIVATE KEY-----
      name: small-cell
network-properties:
  network:
    name: tas-Deployment
  other_availability_zones:
  - name: az2
  - name: az1
  singleton_availability_zone:
    name: az2
resource-config:
  isolated_diego_cell_small_cell:
    max_in_flight: 4%
    instance_type:
      id: medium.disk
    instances: 3
  isolated_router_small_cell:
    max_in_flight: 1
    instance_type:
      id: automatic
    instances: 0  # Shared routing - no dedicated routers
errand-config:
  smoke_tests_isolation:
    post-deploy-state: true
```

### Apply Configuration

```bash
# Configure small-cell segment
om configure-product --config /tmp/small-cell-config.yml

# Configure medium-cell segment
om configure-product --config /tmp/medium-cell-config.yml

# Configure large-cell segment
om configure-product --config /tmp/large-cell-config.yml
```

### Two-Step Configuration (If Needed)

If you encounter errors with certain properties (like `.isolated_router.*` properties on fresh tiles), configure in two steps:

```bash
# Step 1: Apply product properties only
om configure-product --config /tmp/small-cell-props-only.yml

# Step 2: Apply resource configuration separately
om configure-product --config /tmp/small-cell-resources.yml
```

---

## Step 6: Deploy via Ops Manager

### Option A: Deploy All Changes

```bash
# Apply all pending changes
om apply-changes
```

### Option B: Deploy Specific Products

```bash
# Deploy only isolation segment products
om apply-changes \
    --product-name p-isolation-segment-small-cell \
    --product-name p-isolation-segment-medium-cell \
    --product-name p-isolation-segment-large-cell
```

### Option C: Deploy via UI

1. Navigate to Ops Manager UI
2. Click "Review Pending Changes"
3. Select the isolation segment products
4. Click "Apply Changes"

### Monitor Deployment

```bash
# Watch deployment progress
om apply-changes --skip-deploy-products=false 2>&1 | tee deployment.log

# Or check via BOSH
bosh -e ENV tasks --recent
```

---

## Step 7: Register Segments in Cloud Controller

After deployment completes, register each segment in Cloud Controller.

```bash
# Login to CF
cf login -a "$CF_API" -u "$CF_USERNAME" -p "$CF_PASSWORD" --skip-ssl-validation

# Register each segment
cf create-isolation-segment small-cell
cf create-isolation-segment medium-cell
cf create-isolation-segment large-cell

# Verify registration
cf isolation-segments
```

### Enable Segments for Organizations

```bash
# Enable segment for an org
cf enable-org-isolation my-org small-cell

# Optional: Set as org default
cf set-org-default-isolation-segment my-org small-cell

# Assign to a specific space
cf set-space-isolation-segment my-space small-cell
```

---

## Quirks and Troubleshooting

### Common Issues

#### 1. "Property not found" Errors

**Problem:** `om configure-product` fails with errors like:
```text
property '.isolated_router.drain_timeout' is not a property
```

**Cause:** Fresh replicated tiles don't have router-specific properties until after first deployment.

**Solution:** Remove `.isolated_router.*` properties from your config file, or configure properties and resources in separate steps.

#### 2. "Unable to find job guid" Errors

**Problem:** Resource configuration fails with:
```bash
unable to find job guid for job 'isolated_diego_cell'
```

**Cause:** Replicated tiles have suffixed job names.

**Solution:** Use the correct job names:
- `isolated_diego_cell_small_cell` (not `isolated_diego_cell`)
- `isolated_router_small_cell` (not `isolated_router`)

#### 3. Tile Not Found After Upload

**Problem:** `om stage-product` can't find the uploaded product.

**Solution:** Use the full product name with prefix:
```bash
# Wrong
om stage-product --product-name small-cell --product-version 10.2.5

# Correct
om stage-product --product-name p-isolation-segment-small-cell --product-version 10.2.5
```

#### 4. Segment Not Registered

**Problem:** Apps fail to deploy to segment with "isolation segment not found" error.

**Cause:** Segment wasn't registered in Cloud Controller after tile deployment.

**Solution:** Register the segment:
```bash
cf create-isolation-segment small-cell
```

### Debugging Commands

```bash
# Check staged products
om staged-products

# Check available products (uploaded but not staged)
om available-products

# Get full staged config for a product
om staged-config -p p-isolation-segment-small-cell -c > /tmp/staged-config.yml

# Check BOSH deployments
bosh deployments

# Check Diego cells in segment
bosh -d p-isolation-segment-<guid> vms

# Check CF isolation segments
cf isolation-segments
cf org <org-name> --guid
cf curl "/v3/isolation_segments"
```

---

## Configuration Reference

### Export Existing Configuration

To see all available properties and their current values:

```bash
# Export full staged config
om staged-config -p p-isolation-segment-small-cell -c > /tmp/full-config.yml

# Get config template from tile
om config-template --product-path ~/Downloads/small-cell-10.2.5.pivotal \
    --output-directory /tmp/p-isolation-segment-small-cell
```

### Shared Routing vs Dedicated Routing

**Shared Routing (Recommended for most cases):**

```yaml
resource-config:
  isolated_router_small_cell:
    instances: 0  # No dedicated routers
```

Apps route through existing TAS Gorouters. Simpler to manage, no additional load balancer configuration needed.

**Dedicated Routing:**

```yaml
resource-config:
  isolated_router_small_cell:
    instances: 2  # Dedicated routers for this segment
```

Requires additional load balancer configuration and DNS entries.

### Cell Sizing Examples

```yaml
# Small cells (3 cells, automatic sizing)
resource-config:
  isolated_diego_cell_small_cell:
    instances: 3
    instance_type:
      id: automatic

# Medium cells (5 cells, specific size)
resource-config:
  isolated_diego_cell_medium_cell:
    instances: 5
    instance_type:
      id: 2xlarge.disk  # Or your IaaS-specific type

# Large cells (10 cells)
resource-config:
  isolated_diego_cell_large_cell:
    instances: 10
    instance_type:
      id: automatic
```

### Required Properties Checklist

| Property | Purpose | Required |
|----------|---------|----------|
| `.properties.compute_isolation.enabled.isolation_segment_name` | Segment identifier | Yes |
| `.properties.routing_table_sharding_mode` | Routing configuration | Yes |
| `.properties.networking_poe_ssl_certs` | SSL certificate for apps | Yes |
| `network-properties.network` | Network assignment | Yes |
| `network-properties.other_availability_zones` | AZ placement | Yes |
| `resource-config.isolated_diego_cell_*` | Cell count | Yes |
| `resource-config.isolated_router_*` | Router count (0 for shared) | Yes |

---

## Quick Reference

### Complete Workflow Commands

```bash
# 1. Download tile (if needed)
pivnet download-product-files --product-slug='p-isolation-segment' \
    --release-version='10.2.5+LTS-T' --glob='*.pivotal' --accept-eula

# 2. Download Replicator
./scripts/isolation-segment-tile-migration.sh download-replicator --version '10.2.5+LTS-T'

# 3. Replicate tile
/tmp/replicator -name small-cell -path p-isolation-segment-10.2.5.pivotal \
    -output small-cell-10.2.5.pivotal

# 4. Upload and stage
om upload-product --product small-cell-10.2.5.pivotal
om stage-product --product-name p-isolation-segment-small-cell --product-version 10.2.5

# 5. Configure
om configure-product --config small-cell-config.yml

# 6. Deploy
om apply-changes --product-name p-isolation-segment-small-cell

# 7. Register
cf create-isolation-segment small-cell
cf enable-org-isolation my-org small-cell
```

### Naming Conventions Summary

| Segment Name | Product Name | Diego Cell Job | Router Job |
|--------------|--------------|----------------|------------|
| `small-cell` | `p-isolation-segment-small-cell` | `isolated_diego_cell_small_cell` | `isolated_router_small_cell` |
| `medium-cell` | `p-isolation-segment-medium-cell` | `isolated_diego_cell_medium_cell` | `isolated_router_medium_cell` |
| `large-cell` | `p-isolation-segment-large-cell` | `isolated_diego_cell_large_cell` | `isolated_router_large_cell` |

---

## See Also

- [Isolation Segments Performance and Density Guide](isolation-segments-performance-density.md)
- [Isolation Segment Tile Migration Script](scripts/isolation-segment-tile-migration.sh)
- [Broadcom Documentation: Installing Isolation Segments](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/6-0/eart/installing-pcf-is.html)
