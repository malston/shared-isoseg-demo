# Isolation Segments Demo Recording - Design Document

**Date**: 2026-01-09
**Status**: Approved for implementation

## Purpose

Create a customer demonstration video showing how to deploy and use isolation segments with shared routing in TAS/Cloud Foundry, featuring two personas to illustrate the operator and developer experiences.

## Design Decisions

### Format & Production

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Recording format | Terminal + Ops Manager UI | Shows both CLI efficiency and UI visibility |
| Narration | Silent recording, voice-over later | Cleaner audio, easier to fix mistakes |
| Wait handling | Cut and resume | Simple editing, keeps pacing tight |
| Target duration | 20-30 minutes | Comfortable pace with brief explanations |

### Demo Scope

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Tile flow | Full journey | Customer needs confidence to replicate entire workflow |
| Segments | Single (large-cell, 1 cell) | Keeps demo focused; verbally mention "repeat for more" |
| Persona structure | Sequential (Operator → Developer) | Clean separation, easier to record and explain |
| Apps | Spring Music + cf-env | Existing apps, contrasts Java heavyweight vs Go lightweight |

### Verification Levels

| Persona | Verification Level | What They See |
|---------|-------------------|---------------|
| Platform Operator | Full 4-layer | CF CLI, BOSH placement, Diego metrics, app env vars |
| App Developer | Moderate | `cf space` + app endpoint confirmation |

### Developer Migration Story

- **Approach**: Informed migration (not discovery)
- **Notification**: Developer receives message to restage by date
- **Action**: Single `cf restage` command
- **Verification**: `cf space` shows segment, app still works

## Two-Act Structure

### Act 1: Platform Operator (~15-18 min)

**Scene 1.1 - Tile Acquisition** (~3 min)
- Download isolation segment tile via pivnet
- Download Replicator tool
- Run replicate-tile to create `p-isolation-segment-large-cell`

**Scene 1.2 - Ops Manager Installation** (~4 min)
- Upload tile to Ops Manager
- Stage and configure (AZs, cell count, networking)
- Apply Changes [CUT during wait]

**Scene 1.3 - Segment Registration** (~2 min)
- `cf create-isolation-segment large-cell`
- `cf enable-org-isolation large-cell -o <org>`
- Create test space and assign segment

**Scene 1.4 - Operator Validation** (~5 min)
- Deploy cf-env to test space
- Run full 4-layer verification
- Confirm app responds
- "Segment validated, ready for tenants"

### Act 2: App Developer (~8-10 min)

**Scene 2.1 - "Before" State** (~2 min)
- Developer targets their space
- Shows Spring Music running
- `cf space` shows no isolation segment

**Scene 2.2 - Migration Notice** (~1 min)
- Simulated notification display
- "Please restage your apps by [date]"

**Scene 2.3 - Restage** (~2 min)
- `cf restage spring-music`
- Wait for completion (real-time)

**Scene 2.4 - Verification** (~3 min)
- `cf space` now shows isolation segment
- App still works at same URL
- "Zero code changes, zero route changes"

## Key Messages

1. **For Operators**: "Validate thoroughly before notifying developers"
2. **For Developers**: "Just restage - everything else stays the same"
3. **Overall**: "Isolation segments provide workload isolation with zero disruption to developer workflows"

## Pre-Recording Requirements

### Environment
- TAS foundation with Ops Manager
- At least 1 Diego cell available
- `om`, `cf`, `pivnet` CLIs configured

### Pre-deployed
- Spring Music on shared space (developer's "existing app")
- cf-env built and ready to push (operator's test app)

### Configuration
- `large-cell-vars.yml` modified to 1 cell
- SSL certs in secrets folder if needed

### Recording Setup
- Clean terminal history
- Readable font size (14-16pt)
- Browser at 100-110% zoom
- Credentials in environment variables (no typing passwords)

## Deliverables

1. **`docs/demo-recording-runbook.md`** - Step-by-step commands with [CUT]/[RESUME] markers
2. **`docs/demo-narration-script.md`** - Voice-over text with timing cues
3. **Modified `large-cell-vars.yml`** - 1 cell for lab environment
