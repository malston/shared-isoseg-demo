# Using Isolation Segments to Improve Performance and App Instance Density

**Objective:** Leverage isolation segments to improve application performance and Diego cell density while minimizing impact to existing production workloads.

**Approach:** Shared routing with targeted isolation and gradual opt-in migration.

---

## Table of Contents

1. [Strategy Overview](#strategy-overview)
2. [Density Trade-offs](#density-trade-offs)
3. [Keep Existing Workloads Untouched](#keep-existing-workloads-untouched)
4. [Create Performance-Optimized Segments](#create-performance-optimized-segments)
5. [Gradual Migration (Opt-In Model)](#gradual-migration-opt-in-model)
6. [Performance Benefits Without Disruption](#performance-benefits-without-disruption)
7. [Minimal Operational Impact](#minimal-operational-impact)
8. [Capacity Planning Example](#capacity-planning-example)
9. [Monitoring During Migration](#monitoring-during-migration)
10. [Rollback Plan](#rollback-plan)
11. [Implementation Summary](#implementation-summary)
12. [See Also](#see-also)

**📋 For step-by-step deployment instructions, see [Deployment Workflow Guide](isolation-segment-deployment-workflow.md)**

---

## Automation Scripts

This guide includes two automation scripts for managing isolation segments:

### isolation-segment-tile-migration.sh (SUPPORTED - Production)

**Use for:** Production deployments that require Broadcom support

- Uses official Isolation Segment tile via Ops Manager
- Fully supported by Broadcom
- Commands: `install-tile`, `configure-segment`, `register-segment`
- Requires: `om` CLI and Ops Manager access

**Example:**

```bash
./scripts/isolation-segment-tile-migration.sh install-tile --tile-path isolation-segment-6.0.x.pivotal
./scripts/isolation-segment-tile-migration.sh configure-segment --name large-cell --cell-count 120
./scripts/isolation-segment-tile-migration.sh register-segment --name large-cell
```

### isolation-segment-migration.sh (TESTING ONLY - Unsupported)

**Use for:** Quick testing and development environments only

- Uses direct BOSH deployment (bypasses Ops Manager)
- NOT supported by Broadcom for production use
- Faster for testing but lacks tile management features
- Commands: `create-segment`, `migrate`, `monitor`, `rollback`, `validate`
- Requires: BOSH Director access

**Example:**

```bash
./scripts/isolation-segment-migration.sh create-segment --name test-segment --cell-size 4/32 --count 10 --register
```

**⚠️ Important:** For production deployments, always use the tile-based script to maintain Broadcom support.

---

## Strategy Overview

**Recommended Approach: Shared Routing with Targeted Isolation**

- Deploy isolation segments with **shared routing** (uses existing TAS Gorouters)
- Keep all existing apps on shared segment (zero disruption)
- Create optimized segments for specific workload types
- Gradual opt-in migration (test → validate → rollout)
- Easy rollback if needed

**Key Benefit:** Provides **compute isolation** (dedicated Diego cells) **without network isolation** (no routing infrastructure changes) = lowest-impact implementation.

### Zero Impact to Developers and CI/CD Pipelines

**Critical advantage:** Migration is completely transparent to developers and deployment pipelines.

**How it works:**

1. Platform operator assigns space to isolation segment: `cf set-space-isolation-segment production-space large-cell`
2. Platform operator restarts apps: `cf restart app-name`
3. Apps now run on isolation segment - **developers and pipelines notice nothing**

**What stays identical:**

- Space names and org structure
- `cf push` commands and workflows
- CI/CD pipeline configurations (GitHub Actions, Jenkins, Concourse, etc.)
- Application manifests and configuration
- Routes, URLs, and DNS
- Environment variables and service bindings

**Example - Pipeline continues unchanged:**

```bash
# CI/CD pipeline script - NO CHANGES NEEDED
cf target -o production-org -s production-space
cf push myapp
# App automatically deploys to isolation segment
```

This means you can migrate entire teams, business units, or workload types to optimized segments without coordinating with developers or updating hundreds of pipelines.

---

## Density Trade-offs

**⚠️ Important:** Higher density is not always better. Before pursuing larger cells for increased density, understand the trade-offs.

### When Density Becomes a Problem

**Increased Blast Radius:**

When a large, dense cell fails, you lose more app instances at once. A single 8/64 cell failure impacts roughly twice as many apps as a 4/32 cell failure.

- More apps go down simultaneously
- Recovery creates a "thundering herd" as Diego reschedules everything at once
- Correlated failures become more impactful

**Capacity Headroom Math Changes:**

With fewer, larger cells, N+1 redundancy requires proportionally more spare capacity:

- **100 × 4/32 cells:** Losing 1 cell = 1% capacity loss. Need ~2-3 spare cells.
- **50 × 8/64 cells:** Losing 1 cell = 2% capacity loss. Need ~2-3 spare cells, but each spare is larger.
- **Over-provisioned clusters** with large cells may not have enough headroom to absorb a failure—apps have nowhere to evacuate to.

**Evacuation and Recovery Time:**

Larger cells take longer to drain during maintenance or failure:

- More containers to evacuate
- More network connections to re-establish
- Diego scheduler works harder to place displaced apps
- Rolling updates take longer

**Noisy Neighbor Amplification:**

More containers on a single host means more potential for resource contention:

- CPU scheduling becomes more complex
- Memory pressure affects more apps
- Disk I/O contention increases
- Network bandwidth competition

### Right-Sizing Guidance

| Scenario | Recommended Approach |
|----------|---------------------|
| Stable, predictable workloads | Larger cells (8/64) may be appropriate |
| Variable or bursty workloads | Smaller cells (4/32) provide better isolation |
| High availability requirements | More, smaller cells reduce blast radius |
| Cost optimization priority | Larger cells reduce overhead, but balance against risk |
| Mixed workload types | Smaller cells allow finer-grained placement |

### The Over-Provisioning Trap

If your cluster has significantly more capacity than needed:

1. **Don't** automatically consolidate onto fewer, larger cells
2. **Do** consider whether the "waste" is actually providing fault tolerance
3. **Do** model failure scenarios: "If I lose my largest cell, can the remaining cells absorb the load?"

**Rule of thumb:** If losing a single cell would cause app placement failures, your cells are too large or your headroom is too small.

---

## Keep Existing Workloads Untouched

### Initial Setup (Zero Impact)

**Configuration:**

- Deploy isolation segment tile with **shared routing** enabled
- In TAS tile Networking: Keep `Accept requests for all isolation segments` (default)
- No DNS changes required
- No load balancer changes required
- No network topology changes required

**Result:**

- Existing apps continue using shared Diego cells
- Existing apps continue using TAS Gorouters
- Zero downtime
- Zero configuration changes to running workloads

**Network Path (Unchanged):**

```text
Client → Existing LB → TAS Gorouter → App (Shared or Segment)
```

---

## Create Performance-Optimized Segments

### Segment Strategy Examples

#### Large-Cell Segment

**Purpose:** Use larger VMs for workloads where bin-packing efficiency outweighs fault isolation concerns

```bash
cf create-isolation-segment large-cell
```

**BOSH Configuration:**

- Cell size: **8 vCPU / 64GB** (vs default 4/32)
- Benefits:
  - Better bin-packing efficiency (fewer VMs for same capacity)
  - Reduced overhead (fewer Garden containers, Rep processes)
  - Higher memory utilization (larger chunks)
  - ~50% reduction in VM count for equivalent capacity

**Best For:**

- Microservices with predictable resource usage
- Web applications with moderate resource requirements
- Background workers
- Non-memory-intensive workloads

#### High-Performance Segment

**Purpose:** Dedicated resources, no noisy neighbors

```bash
cf create-isolation-segment high-performance
```

**BOSH Configuration:**

- Cell size: **4 vCPU / 32GB** (same as default, but isolated)
- Benefits:
  - Guaranteed resources (no contention with dev/test)
  - Predictable performance under load
  - Isolated from experimental workloads
  - Priority scheduling

**Best For:**

- Customer-facing production applications
- Revenue-critical workloads
- Applications with strict SLAs
- Performance-sensitive APIs

#### High-Memory Segment

**Purpose:** Optimized for memory-intensive workloads

```bash
cf create-isolation-segment high-memory
```

**BOSH Configuration:**

- Cell size: **4 vCPU / 128GB** (4:1 memory-to-CPU ratio)
- Benefits:
  - Better memory:CPU ratio for analytics workloads
  - Support for large heap sizes
  - Reduced memory pressure
  - Fewer OOM kills

**Best For:**

- Data processing applications
- Analytics workloads
- In-memory caching (Redis, Memcached)
- Large Java applications

#### High-CPU Segment

**Purpose:** Optimized for compute-intensive workloads

```bash
cf create-isolation-segment high-cpu
```

**BOSH Configuration:**

- Cell size: **8 vCPU / 32GB** (1:4 memory-to-CPU ratio)
- Benefits:
  - Better CPU:memory ratio for compute workloads
  - Support for parallel processing
  - Reduced CPU throttling
  - Improved throughput

**Best For:**

- Image/video processing
- Cryptographic operations
- Machine learning inference
- API aggregation services

---

## Gradual Migration (Opt-In Model)

### Zero-Downtime Migration Process

#### Phase 1: Create and Test (Week 1-2)

```bash
# Step 1: Create new org/space for testing
cf create-space large-cell-test -o production-org

# Step 2: Entitle org to use new segment
cf enable-org-isolation production-org large-cell

# Step 3: Assign test space to segment
cf set-space-isolation-segment large-cell-test large-cell

# Step 4: Push test application
cf target -s large-cell-test
cf push test-app

# Step 5: Validate
cf app test-app
# Verify: isolation segment: large-cell

# Step 6: Performance testing
# - Load testing
# - Response time analysis
# - Resource utilization monitoring
# - Compare against shared segment baseline
```

#### Phase 2: Pilot Migration (Week 3-4)

```bash
# Identify low-risk production apps for pilot
# Examples: internal tools, non-critical services, background workers

# Migrate pilot apps
cf set-space-isolation-segment internal-tools-space large-cell
cf restart app1
cf restart app2

# Monitor for 1-2 weeks:
# - Application health
# - Performance metrics
# - Error rates
# - User feedback
```

#### Phase 3: Gradual Rollout (Month 2-4)

```bash
# Wave 1: 25% of production apps (Month 2)
cf set-space-isolation-segment batch1-space large-cell
# Restart apps in batches, monitor each batch

# Wave 2: 25% of production apps (Month 3)
cf set-space-isolation-segment batch2-space large-cell
# Restart apps in batches, monitor each batch

# Wave 3: 25% of production apps (Month 4)
cf set-space-isolation-segment batch3-space large-cell
# Restart apps in batches, monitor each batch

# Wave 4: Remaining apps (Month 5+)
# Based on learnings from previous waves
```

#### Phase 4: Optimization (Ongoing)

```bash
# Fine-tune segment assignments based on:
# - Actual resource usage patterns
# - Performance requirements
# - Cost optimization
# - Capacity constraints

# Move apps between segments as needed
cf set-space-isolation-segment analytics-space high-memory
cf restart analytics-app
```

---

## Performance Benefits Without Disruption

### Density Improvements

**Larger Cells = Better Bin-Packing:**

- **8/64 cells vs 4/32 cells**: 50% fewer VMs for same capacity
- **Example**:
  - Current: 100 apps × 2GB = 200GB memory
  - 4/32 cells: Need 7 cells (224GB capacity)
  - 8/64 cells: Need 4 cells (256GB capacity)
  - **Result**: 43% fewer VMs, reduced overhead

**Reduced Infrastructure Overhead:**

- Fewer Garden containers to manage
- Fewer Rep processes
- Fewer BOSH agent processes
- Lower network overhead (fewer cells = fewer connections)

**Higher Memory Utilization:**

- Larger cells = Larger memory chunks available
- Better app placement flexibility
- Reduced memory fragmentation
- Improved Diego scheduler efficiency

### Performance Improvements

**Dedicated Resources = No Noisy Neighbors:**

- Production apps isolated from dev/test workloads
- Critical apps get guaranteed resources
- Predictable performance under load
- No resource contention from experimental apps

**Workload-Specific Optimization:**

- Right-sized cells for specific app types
- Optimized memory:CPU ratios
- Better resource utilization
- Reduced over-provisioning

**Consistent Performance:**

- Reduced variability in response times
- Fewer CPU throttling events
- Fewer memory pressure situations
- More predictable scaling behavior

---

## Minimal Operational Impact

### What DOESN'T Change

✅ **Application Routes:**

- Same DNS names
- Same URLs
- Same domain configuration
- No route changes required

✅ **Routing Infrastructure:**

- Existing TAS Gorouters handle all traffic
- No new Gorouter instances needed
- No load balancer configuration changes
- Shared routing maintained

✅ **SSL/TLS:**

- Same certificates
- Same termination points
- No certificate reissuance needed

✅ **Developer Experience:**

- `cf push` works identically
- Same CF CLI commands
- Same manifest files
- No workflow changes

✅ **Observability:**

- Same Loggregator pipeline
- Same logging endpoints
- Same metrics collection
- Same monitoring dashboards (just add segment filters)

✅ **Security:**

- Same security groups
- Same network policies
- Same authentication/authorization
- No compliance re-validation needed

### What DOES Change

⚠️ **Infrastructure:**

- Additional Diego cells deployed (new BOSH instances)
- Additional ESXi host resources consumed
- Potential cost increase

⚠️ **App Placement:**

- Apps opt-in to new segments (controlled migration)
- Requires `cf restart` to move between segments
- Space/org administrators control placement

⚠️ **Capacity Planning:**

- Need to plan capacity for multiple segments
- Monitor utilization across segments
- Balance workloads between segments

---

## Capacity Planning Example

### Current State

**Cluster Configuration:**

- 470 Diego cells at **4/32** (4 vCPU, 32GB RAM)
- 7,000-8,000 app instances
- Mixed workload types on shared segment

**Total Capacity:**

- vCPU: 470 × 4 = 1,880 vCPU
- Memory: 470 × 32GB = 15,040 GB

### Optimized State: Large-Cell Segment

**Scenario:** Deploy large-cell segment for 50% of apps

#### Infrastructure Changes

**Deploy New Segment:**

- Add 120 Diego cells at **8/64** (8 vCPU, 64GB RAM)
- Placement tag: `large-cell`

**New Segment Capacity:**

- vCPU: 120 × 8 = 960 vCPU
- Memory: 120 × 64GB = 7,680 GB

**Total Cluster Capacity:**

- vCPU: 1,880 + 960 = 2,840 vCPU
- Memory: 15,040 + 7,680 = 22,720 GB

#### Density Improvement Calculation

**Without Optimization (All 4/32 cells):**

- 7,500 app instances × 512MB average = 3,750 GB
- Required cells: 3,750 / 28GB usable ≈ 134 cells
- With N-1 redundancy: ~160 cells needed

**With Optimization (50% on 8/64 cells):**

- 3,750 app instances on large-cell segment
- 3,750 GB / 60GB usable per 8/64 cell ≈ 63 cells
- 3,750 app instances on shared segment: ~80 cells (4/32)
- **Total: ~143 cells vs 160 cells = 11% reduction**

**Benefits:**

- Same app capacity with fewer VMs
- Better bin-packing on larger cells
- Reduced infrastructure overhead
- Cost savings on ESXi host resources

### Rollout Timeline

**Month 1: Deploy Infrastructure**

- Deploy 120 cells in large-cell segment
- Configure BOSH placement tags
- Register segment in Cloud Controller
- Test with pilot apps

**Month 2-5: Gradual Migration (25% per month)**

- Month 2: Migrate 1,875 app instances (25%)
- Month 3: Migrate 1,875 app instances (25%)
- Month 4: Migrate 1,875 app instances (25%)
- Month 5: Migrate remaining 1,875 app instances (25%)

**Month 6: Optimization**

- Analyze utilization across segments
- Right-size cell counts
- Potentially decommission underutilized shared cells
- Fine-tune app placement

---

## Monitoring During Migration

### Diego Cell Capacity Metrics

#### Per-Segment Capacity Checks

**Note:** For tile-based deployments, BOSH deployment names are generated by Ops Manager (e.g., `cf-abc123def456` and `p-isolation-segment-xyz789abc`), not simple names like `cf` or `large-cell`.

```bash
# Find deployment names
bosh -e ENV deployments

# Get TAS deployment name
TAS_DEPLOYMENT=$(bosh -e ENV deployments --json | jq -r '.Tables[0].Rows[] | select(.name | startswith("cf-")) | .name')

# Get isolation segment deployment name
ISO_DEPLOYMENT=$(bosh -e ENV deployments --json | jq -r '.Tables[0].Rows[] | select(.name | startswith("p-isolation-segment-")) | .name')

# Shared segment capacity (TAS Diego cells)
bosh -e ENV -d "$TAS_DEPLOYMENT" ssh diego_cell/0 \
  -c "curl -s localhost:1800/state | jq .AvailableResources"

# Isolation segment capacity (note: tile uses 'isolated_diego_cell' instance group)
bosh -e ENV -d "$ISO_DEPLOYMENT" ssh isolated_diego_cell/0 \
  -c "curl -s localhost:1800/state | jq .AvailableResources"

# Expected output:
{
  "AvailableResources": {
    "MemoryMB": 28672,  # ~28GB available on 4/32 cell
    "DiskMB": 245760,
    "Containers": 245
  }
}
```

#### Cluster-Wide Capacity View

```bash
# All cells in shared segment
bosh -e ENV -d cf instances --details | grep diego_cell

# All cells in large-cell segment
bosh -e ENV -d large-cell instances --details | grep diego_cell
```

### Application Performance Comparison

#### Before Migration (Shared Segment)

```bash
# Check current segment assignment
cf app myapp
# Shows: isolation segment: shared

# Baseline metrics
cf app myapp
# Note: instances, memory, disk, CPU%

# Application logs
cf logs myapp --recent | grep "response_time"
```

#### After Migration (Isolation Segment)

```bash
# Verify segment assignment
cf app myapp
# Shows: isolation segment: large-cell

# Compare metrics
cf app myapp
# Compare: CPU%, memory%, response times

# Monitor for issues
cf events myapp
# Look for crashes, restarts, errors
```

#### Key Metrics to Track

| Metric | Baseline (Shared) | Target (Segment) | Threshold |
|--------|-------------------|------------------|-----------|
| Average Response Time | X ms | < X ms | +10% max |
| 95th Percentile Response Time | Y ms | < Y ms | +10% max |
| CPU Utilization | A% | Similar | ±15% |
| Memory Utilization | B% | Similar | ±15% |
| Error Rate | C% | ≤ C% | No increase |
| Request Rate | D req/s | ≥ D req/s | No decrease |

### Segment Utilization Monitoring

```bash
# Cloud Controller API: Apps per segment
cf curl "/v3/apps?isolation_segment_guids=$(cf isolation-segment large-cell --guid)" \
  | jq '.pagination.total_results'

# Diego cell utilization across segment
for i in {0..9}; do
  echo "Cell diego_cell/$i:"
  bosh -e ENV -d large-cell ssh diego_cell/$i \
    -c "curl -s localhost:1800/state | jq '.AvailableResources.MemoryMB'"
done
```

### Alerting Configuration

**Key Alerts to Configure:**

1. **Low Capacity Warning:**
   - Trigger: Segment capacity < 25%
   - Action: Plan to add cells or rebalance apps

2. **High Utilization Alert:**
   - Trigger: Segment utilization > 85%
   - Action: Add cells to segment

3. **App Migration Failure:**
   - Trigger: App fails to start after segment assignment
   - Action: Investigate logs, consider rollback

4. **Performance Degradation:**
   - Trigger: Response time > baseline + 20%
   - Action: Investigate app performance, consider rollback

---

## Rollback Plan

### Scenario 1: App Performance Issues After Migration

**Symptoms:**

- Increased response times
- Higher error rates
- Resource exhaustion

**Immediate Rollback:**

```bash
# Move space back to shared segment
cf reset-space-isolation-segment SPACE-NAME

# Restart affected apps
cf restart APP-NAME

# Verify return to shared segment
cf app APP-NAME
# Shows: isolation segment: shared (or no segment listed)
```

**Validation:**

- Monitor app metrics for 1-2 hours
- Compare against baseline
- Investigate root cause before re-attempting migration

### Scenario 2: Segment Capacity Issues

**Symptoms:**

- Apps fail to start (insufficient resources)
- Staging failures
- Diego scheduler errors

**Resolution Options:**

**Option A: Add capacity to segment**

```bash
# Scale up Diego cells in segment
bosh -e ENV -d large-cell manifest > manifest.yml
# Edit manifest: increase diego_cell instance count
bosh -e ENV -d large-cell deploy manifest.yml
```

**Option B: Move some apps to different segment**

```bash
# Identify lower-priority apps
# Move to shared segment or different isolation segment
cf set-space-isolation-segment low-priority-space shared
cf restart low-priority-app
```

**Option C: Rollback entire batch**

```bash
# Reset all spaces in migration batch
for space in space1 space2 space3; do
  cf reset-space-isolation-segment $space
done

# Restart all apps (consider using cf curl for automation)
```

### Scenario 3: Segment Infrastructure Issues

**Symptoms:**

- Diego cell health check failures
- BOSH VM issues
- Network connectivity problems

**Immediate Action:**

```bash
# Check BOSH deployment health
bosh -e ENV -d large-cell vms --vitals
bosh -e ENV -d large-cell instances --ps

# Check specific cell health
bosh -e ENV -d large-cell ssh diego_cell/0 -c "monit summary"

# If segment is unhealthy, move all apps off
cf curl /v3/apps?isolation_segment_guids=$(cf isolation-segment large-cell --guid) \
  | jq -r '.resources[].name' > apps.txt

# For each app, move to shared
while read app; do
  cf curl -X PATCH /v3/apps/$(cf app $app --guid) \
    -d '{"relationships":{"space":{"data":{"guid":"'$(cf space SPACE-NAME --guid)'"}}}}}'
done < apps.txt
```

### Rollback Decision Matrix

| Issue | Severity | Rollback Action | Timeline |
|-------|----------|-----------------|----------|
| Minor performance degradation (<10%) | Low | Monitor, optimize | 1-2 days |
| Moderate performance degradation (10-20%) | Medium | Investigate, consider rollback | 2-4 hours |
| Severe performance degradation (>20%) | High | Immediate rollback | <30 minutes |
| App crashes/failures | Critical | Immediate rollback | <15 minutes |
| Segment infrastructure failure | Critical | Evacuate all apps | <15 minutes |

---

## Implementation Summary

### Least-Impact Implementation Path

#### ✅ Phase 1: Deploy with Shared Routing

- Deploy isolation segment tile
- Configure shared routing (no network changes)
- Register segments in Cloud Controller
- **Impact:** Zero to existing workloads

#### ✅ Phase 2: Create Optimized Segments

- Define segment strategy (large-cell, high-performance, etc.)
- Deploy Diego cells with placement tags
- Configure cell sizes based on workload requirements
- **Impact:** Infrastructure addition only

#### ✅ Phase 3: Keep All Existing Apps Unchanged

- All existing apps remain on shared segment
- No restarts required
- No configuration changes
- **Impact:** Zero disruption

#### ✅ Phase 4: Opt-In Migration

- Test with pilot apps first
- Validate performance improvements
- Gradual rollout (25% per month)
- **Impact:** Controlled, measurable, reversible

#### ✅ Phase 5: Monitor and Compare

- Track performance metrics before/after
- Compare segment utilization
- Measure density improvements
- **Impact:** Data-driven optimization

#### ✅ Phase 6: Easy Rollback If Needed

- Simple space reassignment
- App restart to revert
- No infrastructure changes required
- **Impact:** Low-risk, fast recovery

### Key Success Factors

1. **Start with Shared Routing**
   - Lowest operational complexity
   - No network infrastructure changes
   - Easy to implement and rollback

2. **Gradual Opt-In Migration**
   - Test thoroughly before production rollout
   - Monitor each wave before proceeding
   - Build confidence incrementally

3. **Clear Segment Strategy**
   - Define segments based on workload characteristics
   - Right-size cells for target workloads
   - Align segment goals with business needs

4. **Comprehensive Monitoring**
   - Baseline metrics before migration
   - Track performance during migration
   - Compare results against targets

5. **Simple Rollback Plan**
   - Document rollback procedures
   - Test rollback process
   - Maintain shared segment capacity as safety net

### Expected Outcomes

**Performance:**

- ✅ Predictable performance (no noisy neighbors)
- ✅ Reduced resource contention
- ✅ Optimized cell configurations for workload types

**Density:**

- ✅ 10-50% reduction in VM count (depending on cell sizing)
- ✅ Better bin-packing efficiency
- ✅ Higher resource utilization

**Operational Impact:**

- ✅ Zero downtime during deployment
- ✅ Zero changes to existing workloads
- ✅ Gradual, controlled migration
- ✅ Easy rollback if needed

---

## Conclusion

**Isolation segments with shared routing provide compute isolation (dedicated Diego cells for performance and density) without network isolation (no routing infrastructure changes).**

This is the **lowest-impact approach** for improving performance and app instance density while maintaining full operational flexibility and easy rollback options.

The gradual opt-in migration model ensures existing production workloads remain unaffected while new optimized segments are validated and proven before broad adoption.

---

## See Also

- **[Deployment Workflow Guide](isolation-segment-deployment-workflow.md)** - Step-by-step instructions for replicating, installing, and configuring multiple isolation segments
- **[Tile Migration Script](scripts/isolation-segment-tile-migration.sh)** - Automation for tile management
- **[Broadcom TechDocs: Installing Isolation Segments](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/6-0/eart/installing-pcf-is.html)**
