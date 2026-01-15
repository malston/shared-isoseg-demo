#!/usr/bin/env bash
# ABOUTME: Displays the platform migration notification
# ABOUTME: Called by send-developer-notification.sh to show clean output

echo ""
echo "================================================================================"
echo "PLATFORM NOTIFICATION"
echo ""
echo "Subject: Isolation Segment Migration - Action Required"
echo ""
echo "Your space 'dev-space' has been assigned to isolation segment 'large-cell'"
echo "for improved resource allocation and workload isolation."
echo ""
echo "ACTION REQUIRED:"
echo "  Please restage your applications by Friday, January 17, 2026 to"
echo "  complete the migration."
echo ""
echo "  Command: cf restage <app-name>"
echo ""
echo "Questions? Contact platform-team@example.com"
echo "================================================================================"
echo ""
