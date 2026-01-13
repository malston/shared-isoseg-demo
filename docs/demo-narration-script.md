# Isolation Segments Demo - Narration Script

> Voice-over script for post-production. Sync with video timeline.
> Target duration: 20-30 minutes

---

## Introduction

**[0:00 - 0:45]** *Show title slide or Ops Manager dashboard*

> Today we'll demonstrate how to deploy and use isolation segments with shared routing in Tanzu Application Service.
>
> Isolation segments provide workload isolation at the compute layer - your applications run on dedicated Diego cells, separate from other tenants. But here's the key: with shared routing, developers experience zero disruption. Same routes, same deployment commands, same behavior.
>
> We'll show two perspectives: first, the Platform Operator who deploys and validates the segment, then the App Developer who migrates their application with a single command.

---

## Act 1: Platform Operator Experience

### Scene 1.1: Tile Acquisition

**[0:45 - 2:30]**

**[1.1.1 - Download Tile]**
> We start by downloading the Isolation Segment tile from Broadcom's support portal using the Pivnet API. This automation saves time compared to manual downloads through the web interface.

**[1.1.2 - Download Replicator]**
> The Replicator tool is essential when you need multiple isolation segments. It creates separate tile instances from a single base tile, each with a unique product name. This allows you to deploy segments with different cell configurations - for example, large cells for memory-intensive apps, small cells for microservices.

**[1.1.3 - Create Replicated Tile]**
> We create a tile instance named "large-cell." This name becomes part of the product identifier in Ops Manager and will be visible when we register the segment in Cloud Foundry.

---

### Scene 1.2: Ops Manager Installation

**[2:30 - 5:30]**

**[1.2.1 - Upload Tile]**
> The replicated tile uploads to Ops Manager just like any other tile. You can use the CLI for automation, or the web interface for visibility.

**[1.2.2 - Stage Tile]**
> Staging adds the tile to the installation dashboard. It's now ready for configuration.

**[1.2.3 - Configure Tile]**
> Let's walk through the key configuration sections.
>
> **Availability Zones**: We select which AZs host our isolated cells. For high availability, choose multiple zones.
>
> **Diego Cells**: For this lab, we're deploying a single cell. In production, you'd typically deploy multiple cells based on your workload requirements.
>
> **Networking**: Notice we have zero dedicated routers. This is the "shared routing" model - traffic flows through the TAS routers that already handle your other applications. No additional load balancers, no DNS changes, no network reconfiguration.

**[KEY MESSAGE BOX]**
> **Zero infrastructure changes for routing** - shared routers handle traffic for all isolation segments

**[1.2.4 - Apply Changes]**
> We apply changes to deploy the isolation segment. This provisions the Diego cells on your infrastructure.

*[CUT - Apply Changes in progress]*

---

### Scene 1.3: Segment Registration

**[5:30 - 7:30]**

**[RESUME after Apply Changes]**
> The deployment is complete. Now we register the segment in Cloud Foundry's Cloud Controller.

**[1.3.1 - Create Segment]**
> The "create-isolation-segment" command registers the name with Cloud Foundry. This creates the logical segment that spaces can be assigned to. We immediately verify it's registered.

**[1.3.2 - Enable for Org]**
> Organizations must be explicitly entitled to use each isolation segment. This is an important security boundary - it prevents unauthorized use of isolated compute resources. The "cf org" command confirms our org is now entitled to use the segment.

**[1.3.3 - Create Validation Space]**
> Before notifying developers, we create a dedicated validation space. This "iso-validation" space is separate from developer workspaces - it's where operators test the segment before onboarding tenants.

**[1.3.4 - Assign Space to Segment]**
> We assign the validation space to our isolation segment. The "cf space" command confirms the assignment - any apps pushed to this space will now run on the isolated Diego cells.

---

### Scene 1.4: Operator Validation

**[7:30 - 11:00]**

**[1.4.1 - Deploy Test App]**
> We deploy a lightweight test application - "cf-env" - a simple Go app that displays environment information. This validates that workloads can actually run on the isolated cells.

**[1.4.2 - Verify Running]**
> The app is running. Let's access it in the browser to confirm it responds correctly.

**[1.4.3 - IP Verification]**
> We verify the app is running on the isolated cell by comparing IP addresses. The app's instance IP matches the Diego cell IP from BOSH - proving physical isolation.

**[1.4.4 - BOSH Placement Tags]**
> At the infrastructure level, we SSH into the Diego cell and check its placement tags. The output shows "large-cell" - this is what tells Diego to schedule apps from our isolation segment onto this specific cell. This is the definitive proof of isolation at the BOSH layer.

**[KEY MESSAGE BOX]**
> **Placement tags are the mechanism that enforces workload isolation at the infrastructure level**

**[1.4.5 - Ready Declaration]**
> The isolation segment "large-cell" is validated and ready for production workloads. We can now notify development teams to migrate their applications.

---

## Act 2: App Developer Experience

### Scene 2.1: "Before" State

**[11:00 - 13:00]**

**[2.1.1 - Developer Context]**
> Now let's switch to the developer perspective. This developer has an existing application - Spring Music, a Java web app - running on shared Diego cells.

**[2.1.2 - Show Application]**
> Here's the application running. Note the routes, the allocated memory, the buildpack - all the standard Cloud Foundry deployment details.

**[2.1.3 - Check Space]**
> When we check the space configuration, notice there's no isolation segment listed. The app runs on shared Diego cells alongside other tenants' workloads.

**[2.1.4 - Verify Works]**
> The application works perfectly - serving requests, displaying data. This is our baseline before migration.

---

### Scene 2.2: Migration Notice

**[13:00 - 14:00]**

**[2.2.1 - Notification]**
> The developer receives a notification from the platform team. The message is simple:
>
> "Your space has been assigned to isolation segment 'large-cell' for improved resource allocation. Please restage your applications by the specified date."
>
> That's it. One command: "cf restage."

**[KEY MESSAGE BOX]**
> **Developer action required: ONE command - cf restage**

---

### Scene 2.3: Developer Performs Restage

**[14:00 - 16:00]**

**[2.3.1 - Operator Assigns Space]**
> The platform operator assigns the developer's space to the isolation segment. This is a one-time configuration change - developers don't need elevated permissions to trigger this.

**[2.3.2 - Developer Verifies Assignment]**
> The developer can verify their space has been assigned to the isolation segment with "cf space." They'll see the segment name listed.

**[2.3.3 - Restage Command]**
> Now the developer runs the restage command. This rebuilds the application droplet and restarts the app on the new isolated cells.
>
> Notice: no changes to the application code, no changes to the manifest, no changes to the CI/CD pipeline. The same deployment process, the same artifact - just running on different infrastructure.

*[Wait for restage to complete]*

---

### Scene 2.4: Developer Verification

**[16:00 - 19:00]**

**[2.4.1 - Confirm Segment]**
> The space now shows the isolation segment assignment. The app is running on isolated Diego cells.

**[2.4.2 - Application Works]**
> Let's verify the application still works exactly as before. Same URL, same functionality, same user experience.

**[2.4.3 - Zero Changes]**
> Let's highlight what did NOT change:
>
> **Routes**: Same URL, same domain, same path.
>
> **Resources**: Same memory, same disk allocation.
>
> **Buildpack**: Same build process, same dependencies.
>
> The only change is WHERE the app runs - on isolated compute, instead of shared compute.

**[2.4.4 - Physical Verification]**
> We can verify the app is actually running on the isolated Diego cell by comparing IP addresses. The app's instance IP matches the isolated cell IP - proving physical isolation.

**[2.4.5 - Closing Summary]**
> To summarize: the developer ran one command - "cf restage" - and their application is now running on dedicated isolated infrastructure. No code changes, no route changes, no pipeline changes.

**[KEY MESSAGE BOX]**
> **Zero code changes. Zero route changes. Zero pipeline changes. Just restage.**

---

## Closing

**[19:00 - 20:00]**

> To summarize what we've demonstrated:
>
> **For Platform Operators**: Download the tile, replicate for your segment configuration, deploy via Ops Manager, register in Cloud Foundry, validate with a test app. The segment is ready in under an hour.
>
> **For Developers**: Receive a notification, run "cf restage", verify your app works. Migration takes minutes, not days.
>
> Isolation segments with shared routing provide workload isolation without disrupting developer workflows. Your applications stay on the same routes, use the same deployment process, and require zero code changes.
>
> This is transparent migration - developers focus on their applications while the platform provides the isolation your security and compliance teams require.

---

## Key Message Summary

Use these phrases consistently throughout the narration:

| Context | Message |
|---------|---------|
| Routing model | "Shared routers handle traffic for all isolation segments" |
| Developer effort | "One command: cf restage" |
| Code impact | "Zero code changes, zero route changes, zero pipeline changes" |
| Value proposition | "Transparent migration - workload isolation without developer disruption" |

---

## Timing Reference

| Section | Start | End | Duration |
|---------|-------|-----|----------|
| Introduction | 0:00 | 0:45 | 45 sec |
| Scene 1.1 - Tile Acquisition | 0:45 | 2:30 | 1:45 |
| Scene 1.2 - Ops Manager Installation | 2:30 | 5:30 | 3:00 |
| Scene 1.3 - Segment Registration | 5:30 | 7:30 | 2:00 |
| Scene 1.4 - Operator Validation | 7:30 | 11:00 | 3:30 |
| Scene 2.1 - Before State | 11:00 | 13:00 | 2:00 |
| Scene 2.2 - Migration Notice | 13:00 | 14:00 | 1:00 |
| Scene 2.3 - Developer Performs Restage | 14:00 | 16:00 | 2:00 |
| Scene 2.4 - Developer Verification | 16:00 | 19:00 | 3:00 |
| Closing | 19:00 | 20:00 | 1:00 |
| **Total** | | | **~20 min** |

> Note: Actual runtime may vary based on recording pace and cut points.
