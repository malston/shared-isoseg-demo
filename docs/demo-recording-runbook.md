# Isolation Segments Demo Recording Runbook

> Step-by-step commands for recording the isolation segments demonstration.
> Silent recording - voice-over added in post-production.

## Pre-Recording Checklist

### Environment Requirements

- [ ] TAS foundation with Ops Manager accessible
- [ ] At least 1 Diego cell available for isolation segment
- [ ] Network connectivity to Broadcom Support Portal

### CLI Tools Configured

- [ ] `om` CLI authenticated (OM_TARGET, OM_USERNAME, OM_PASSWORD exported)
- [ ] `cf` CLI authenticated (`cf login` completed)
- [ ] `pivnet` CLI available with PIVNET_TOKEN set
- [ ] `jq` installed for JSON parsing

### Pre-Recording Setup

- [ ] Spring Music deployed to shared space (`cf push spring-music`)
- [ ] cf-env app built and ready (`cd apps/cf-env && go build`)
- [ ] Demo org and spaces created:

  ```bash
  cf create-org demo-org
  cf create-space dev-space -o demo-org      # Developer's existing space
  cf create-space iso-validation -o demo-org  # Operator's test space
  ```

- [ ] Terminal font size readable (14-16pt recommended)
- [ ] Browser logged into Ops Manager, zoom 100-110%
- [ ] Screen recording software ready

### Credential Management

- [ ] All credentials in environment variables (no typing passwords on camera)
- [ ] `.envrc` or equivalent sourced with OM_*, CF_*, PIVNET_TOKEN

---

## Act 1: Platform Operator Experience

**Estimated recording time**: 15-18 minutes (before cuts)
**Post-cut duration**: ~12-15 minutes

---

### Scene 1.1: Tile Acquisition

**Duration**: ~3 minutes

#### 1.1.1 - Download Isolation Segment Tile

```bash
# Show the download command (10.2.5+LTS-T resolves to p-isolation-segment-10.2.5-build.2.pivotal)
./scripts/isolation-segment-tile-migration.sh download-tile \
  --version 10.2.5+LTS-T \
  --output-directory ~/Downloads
```

> **Narration cue**: "We start by downloading the Isolation Segment tile from Broadcom's support portal using the Pivnet API."

#### 1.1.2 - Download Replicator Tool

```bash
# Download the replicator for the same release
./scripts/isolation-segment-tile-migration.sh download-replicator \
  --version 10.2.5+LTS-T \
  --output-directory ~/Downloads
```

> **Narration cue**: "The Replicator tool allows us to create multiple isolation segment tiles from a single base tile - each with a unique name."

#### 1.1.3 - Create Replicated Tile

```bash
# Create the large-cell tile
./scripts/isolation-segment-tile-migration.sh replicate-tile \
  --source ~/Downloads/p-isolation-segment-10.2.5-build.2.pivotal \
  --name large-cell \
  --output ~/Downloads
```

> **Narration cue**: "We create a tile instance named 'large-cell' - configured for resource-intensive workloads."

**Checkpoint**: Verify `p-isolation-segment-large-cell-10.2.5.pivotal` was created in ~/Downloads

---

### Scene 1.2: Ops Manager Installation

**Duration**: ~4 minutes (plus Apply Changes wait - CUT)

#### 1.2.1 - Upload Tile to Ops Manager

**[BROWSER]** Navigate to Ops Manager Installation Dashboard

```bash
# Alternative: Upload via CLI
om upload-product --product ~/Downloads/p-isolation-segment-large-cell-10.2.5.pivotal
```

> **Narration cue**: "We upload the replicated tile to Ops Manager."

**[BROWSER]** Show tile appearing in "Available Products" section

#### 1.2.2 - Stage the Tile

**[BROWSER]** Click the "+" button next to the tile to stage it

```bash
# Alternative: Stage via CLI
om stage-product \
  --product-name p-isolation-segment-large-cell \
  --product-version 10.2.5
```

**[BROWSER]** Show tile now appears in Installation Dashboard

#### 1.2.3 - Configure the Tile

**[BROWSER]** Click on the tile to open configuration

Walk through key configuration sections:

1. **Assign AZs and Networks** - Show AZ selection
2. **Isolated Diego Cells** - Point out cell count (1 for lab)
3. **Networking** - Note: 0 routers (shared routing mode)

> **Narration cue**: "Key settings: We're using 1 Diego cell for this lab, and zero dedicated routers - traffic flows through the shared TAS routers."

#### 1.2.4 - Apply Changes

**[BROWSER]** Return to Installation Dashboard, click "Review Pending Changes"

**[BROWSER]** Select only the isolation segment tile, click "Apply Changes"

---

### [CUT] - Apply Changes in Progress

> Stop recording. Wait for Apply Changes to complete.
> Resume when deployment is successful.

---

### [RESUME] - Apply Changes Complete

**[BROWSER]** Show successful deployment status

> **Narration cue**: "The isolation segment is now deployed. Next, we register it in Cloud Foundry."

---

### Scene 1.3: Segment Registration

**Duration**: ~2 minutes

#### 1.3.1 - Create Isolation Segment in CF

```bash
# Register the segment in Cloud Controller
cf create-isolation-segment large-cell
```

> **Narration cue**: "We register the segment name with Cloud Foundry's Cloud Controller."

#### 1.3.2 - Enable for Organization

```bash
# Allow the demo org to use this segment
cf enable-org-isolation demo-org large-cell
```

> **Narration cue**: "Organizations must be explicitly entitled to use each isolation segment."

#### 1.3.3 - Assign Segment to Validation Space

```bash
# Assign to operator's test space
cf set-space-isolation-segment iso-validation large-cell
```

> **Narration cue**: "Before notifying developers, we'll validate the segment with a test application."

#### 1.3.4 - Verify Segment Configuration

```bash
# Confirm segment is registered
cf isolation-segments

# Confirm org entitlement (shows "isolation segments: large-cell")
cf org demo-org

# Confirm space assignment
cf space iso-validation
```

---

### Scene 1.4: Operator Validation

**Duration**: ~5 minutes

#### 1.4.1 - Deploy Test Application

```bash
# Target the validation space
cf target -o demo-org -s iso-validation

# Push cf-env as test app
cd apps/cf-env
cf push cf-env-test -m 64M -k 128M
cd ../..
```

> **Narration cue**: "We deploy a lightweight test application to verify the segment is working correctly."

#### 1.4.2 - Verify Application Running

```bash
# Check app status
cf app cf-env-test

# Get the app URL
cf routes
```

**[BROWSER]** Open app URL to show it's responding

#### 1.4.3 - Verify App Running on Isolated Cell

```bash
# Verify space shows isolation segment
cf space iso-validation

# Compare app host IP with isolated Diego cell IP
echo "App running on: $(curl -s "https://$(cf app cf-env-test | grep routes | awk '{print $2}')/env" | grep CF_INSTANCE_IP | cut -d= -f2)"
echo "Large-cell Diego: $(bosh -d p-isolation-segment-large-cell-2ce92833ad1ce8f6e40a instances --json 2>/dev/null | jq -r '.Tables[0].Rows[0].ips')"
```

> **Narration cue**: "We verify the app is running on the isolated cell by comparing the instance IP with the Diego cell IP. They match - the app is on the large-cell segment."

#### 1.4.4 - Segment Ready Declaration

```bash
# Final confirmation
echo "Isolation segment 'large-cell' validated and ready for tenant workloads"

# Show segment status
cf isolation-segments
```

> **Narration cue**: "The segment is validated. We can now notify development teams to migrate their workloads."

---

## Act 2: App Developer Experience

**Estimated recording time**: 8-10 minutes
**Post-cut duration**: ~6-8 minutes

---

### Scene 2.1: "Before" State

**Duration**: ~2 minutes

#### 2.1.1 - Developer Context

```bash
# Developer targets their existing space (on shared cells)
cf target -o demo-org -s dev-space
```

> **Narration cue**: "Switching to the developer perspective. This developer has an application running on shared Diego cells."

#### 2.1.2 - Show Existing Application

```bash
# List apps in the space
cf apps

# Show Spring Music details
cf app spring-music
```

#### 2.1.3 - Check Current Space Configuration

```bash
# Note: no isolation segment listed (or shows "shared")
cf space dev-space
```

> **Narration cue**: "Notice the space has no isolation segment assigned - the app runs on shared Diego cells."

#### 2.1.4 - Verify Application Works

**[BROWSER]** Open Spring Music URL, click around to show it's functional

```bash
# Get the URL
cf app spring-music | grep routes
```

---

### Scene 2.2: Migration Notice

**Duration**: ~1 minute

#### 2.2.1 - Display Migration Notification

```bash
# Simulated notification (could show email/Slack mockup instead)
cat << 'EOF'
================================================================================
PLATFORM NOTIFICATION

Subject: Isolation Segment Migration - Action Required

Your space 'dev-space' has been assigned to isolation segment 'large-cell'
for improved resource allocation and workload isolation.

ACTION REQUIRED:
  Please restage your applications by Friday, January 17, 2026 to
  complete the migration.

  Command: cf restage <app-name>

Questions? Contact platform-team@example.com
================================================================================
EOF
```

> **Narration cue**: "The developer receives a simple notification - just restage your applications by the specified date."

---

### Scene 2.3: Developer Performs Restage

**Duration**: ~2 minutes

#### 2.3.1 - Assign Space to Isolation Segment

```bash
# Platform operator assigns the space to the isolation segment
cf set-space-isolation-segment dev-space large-cell
```

#### 2.3.2 - Developer Verifies Space Assignment

```bash
cf space dev-space
```

#### 2.3.3 - Restage Application

```bash
# This is the ONLY action the developer needs to take
cf restage spring-music
```

> **Narration cue**: "One command. The developer's existing deployment manifests, routes, and application code remain unchanged."

**Wait for restage to complete** (real-time, ~1-2 minutes)

---

### Scene 2.4: Developer Verification

**Duration**: ~3 minutes

#### 2.4.1 - Confirm Isolation Segment Assignment

```bash
# Space now shows isolation segment
cf space dev-space
```

> **Narration cue**: "The space now shows the isolation segment assignment."

#### 2.4.2 - Verify Application Still Works

**[BROWSER]** Refresh Spring Music URL, click around

```bash
# Check app status
cf app spring-music

# Confirm it's running
curl -s -o /dev/null -w "%{http_code}" https://$(cf app spring-music | grep routes | awk '{print $2}')
```

#### 2.4.3 - Highlight Zero Changes Required

```bash
# Same routes
cf app spring-music | grep routes

# Same memory/disk
cf app spring-music | grep -E "memory|disk"

# Same buildpack
cf app spring-music | grep buildpack
```

> **Narration cue**: "Same routes, same memory allocation, same buildpack. Zero code changes. Zero pipeline changes."

#### 2.4.4 - Verify App Running on Isolated Cell

```bash
# Compare app host IP with isolated Diego cell IP
echo "App running on: $(cf curl /v3/apps/$(cf app spring-music --guid)/processes/web/stats 2>/dev/null | jq -r '.resources[0].host')"
echo "Large-cell Diego: $(bosh -d p-isolation-segment-large-cell-2ce92833ad1ce8f6e40a instances --json 2>/dev/null | jq -r '.Tables[0].Rows[0].ips')"
```

> **Narration cue**: "We can verify the app is running on the isolated cell by comparing the instance IP with the Diego cell IP."

```bash
echo "✓ Confirmed: spring-music is running on the large-cell isolation segment"
```

#### 2.4.5 - Closing Summary

```bash
# Quick recap
echo ""
echo "=== Migration Complete ==="
echo "App: spring-music"
echo "Isolation Segment: large-cell"
echo "Developer action: cf restage (1 command)"
echo "Changes to app code: NONE"
echo "Changes to routes: NONE"
echo "Changes to deployment process: NONE"
```

---

## Post-Recording Checklist

### Cleanup (if needed for re-recording)

```bash
# Remove test app
cf delete cf-env-test -f

# Remove isolation segment assignment
cf reset-space-isolation-segment dev-space
cf reset-space-isolation-segment iso-validation

# Disable org isolation
cf disable-org-isolation demo-org large-cell

# Delete isolation segment
cf delete-isolation-segment large-cell -f
```

### Ops Manager Cleanup (if re-recording)

1. Delete the isolation segment tile from Installation Dashboard
2. Apply Changes to remove the deployment

---

## Recording Notes

### Cuts

- **[CUT]**: Stop recording at this point
- **[RESUME]**: Start recording again
- **[BROWSER]**: Switch to browser view

### Timing Markers

- Add chapter markers at each Scene start
- Note timestamp at each [CUT] for editing reference

### Common Issues

| Issue | Solution |
|-------|----------|
| Tile upload slow | Pre-upload before recording, just show "already staged" |
| cf restage fails | Check app logs: `cf logs spring-music --recent` |
| Segment not showing | Verify: `cf curl /v3/isolation_segments` |
| App not starting on segment | Check cell availability: `bosh -d p-isolation-segment-large-cell-* instances` |
