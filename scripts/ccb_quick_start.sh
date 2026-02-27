#!/bin/bash
# Quick helper to start CCB workers

cd "$(dirname "$0")/.."

echo "[CCB] Starting workers..."
ccb

echo ""
echo "[CCB] Workers started. Available commands:"
echo "  ask shop-fe-dev 'message'   - Send to shop frontend"
echo "  ask admin-fe-dev 'message'  - Send to admin frontend"
echo "  ask backend-dev 'message'   - Send to backend"
echo "  ask qa 'message'            - Send to QA"
echo "  pend <worker>               - Wait for response"
echo "  ping <worker>               - Check status"
