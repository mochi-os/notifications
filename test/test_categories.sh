#!/bin/bash
# Copyright © 2026 Mochisoft OÜ
# SPDX-License-Identifier: AGPL-3.0-only
# This file is part of Mochi, licensed under the GNU AGPL v3 with the
# Mochi Application Interface Exception - see license.txt and license-exception.md.

# Notification Categories Test Suite
# Tests the category-based routing redesign (schema v10).
# Usage: ./test_categories.sh

set -e

CURL_HELPER="/home/alistair/mochi/claude/scripts/curl.sh"

PASSED=0
FAILED=0

pass() {
    echo "[PASS] $1"
    ((PASSED++)) || true
}

fail() {
    echo "[FAIL] $1: $2"
    ((FAILED++)) || true
}

SESSION=$(/home/alistair/mochi/claude/scripts/get-token.sh admin)
if [ -z "$SESSION" ]; then
    echo "Could not get session token" >&2
    exit 1
fi

mint_token() {
    local app="$1"
    curl -s -X POST -b "session=$SESSION" -H "Content-Type: application/json" \
        -d "{\"app\":\"$app\"}" "http://localhost:8081/_/token" \
        | python3 -c "import sys, json; print(json.load(sys.stdin).get('token', ''))"
}

SETTINGS_TOKEN=$(mint_token settings)
if [ -z "$SETTINGS_TOKEN" ]; then
    echo "Could not mint settings app token" >&2
    exit 1
fi

settings_curl() {
    local method="$1"
    local path="$2"
    shift 2
    curl -s -X "$method" -H "Authorization: Bearer $SETTINGS_TOKEN" "$@" \
        "http://localhost:8081/settings$path"
}

echo "=============================================="
echo "Notification Categories Test Suite"
echo "=============================================="

# ============================================================================
# SEEDED CATEGORIES
# ============================================================================

echo ""
echo "--- Seeded categories ---"

RESULT=$(settings_curl GET "/-/notifications/categories")
if echo "$RESULT" | python3 -c "
import sys, json
cats = json.load(sys.stdin).get('data', [])
ids = {c['id'] for c in cats}
sys.exit(0 if 0 in ids else 1)" 2>/dev/null; then
    pass "'No notifications' (id 0) exists"
else
    fail "'No notifications' (id 0) exists" "$RESULT"
fi

if echo "$RESULT" | python3 -c "
import sys, json
cats = json.load(sys.stdin).get('data', [])
names = {c['label'] for c in cats}
sys.exit(0 if 'Normal' in names else 1)" 2>/dev/null; then
    pass "'Normal' category seeded"
else
    fail "'Normal' category seeded" "$RESULT"
fi

if echo "$RESULT" | python3 -c "
import sys, json
cats = json.load(sys.stdin).get('data', [])
defaults = [c for c in cats if c.get('default') == 1]
sys.exit(0 if len(defaults) == 1 else 1)" 2>/dev/null; then
    pass "Exactly one default category"
else
    fail "Exactly one default category" "$RESULT"
fi

# ============================================================================
# CREATE / UPDATE / DELETE
# ============================================================================

echo ""
echo "--- Category CRUD ---"

RESULT=$(settings_curl POST "/-/notifications/categories/create" -d "label=TestCat")
NEW_ID=$(echo "$RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin)['data']['id'])" 2>/dev/null || echo "")
if [ -n "$NEW_ID" ]; then
    pass "Create category (id: $NEW_ID)"
else
    fail "Create category" "$RESULT"
fi

if [ -n "$NEW_ID" ]; then
    RESULT=$(settings_curl POST "/-/notifications/categories/update" -d "id=$NEW_ID&label=Renamed")
    CHECK=$(settings_curl GET "/-/notifications/categories")
    if echo "$CHECK" | python3 -c "
import sys, json, os
cats = json.load(sys.stdin).get('data', [])
nid = int(os.environ['NEW_ID'])
match = next((c for c in cats if c['id'] == nid), None)
sys.exit(0 if match and match['label'] == 'Renamed' else 1)" NEW_ID="$NEW_ID" 2>/dev/null; then
        pass "Rename category"
    else
        fail "Rename category" "$CHECK"
    fi
fi

# Delete: must reassign; deleting id 0 must fail
RESULT=$(settings_curl POST "/-/notifications/categories/delete" -d "id=0&reassign_to=1")
if echo "$RESULT" | grep -q '"error"'; then
    pass "Cannot delete 'No notifications' (id 0)"
else
    fail "Cannot delete 'No notifications' (id 0)" "$RESULT"
fi

if [ -n "$NEW_ID" ]; then
    RESULT=$(settings_curl POST "/-/notifications/categories/delete" -d "id=$NEW_ID&reassign_to=0")
    if echo "$RESULT" | grep -q '"data":{}'; then
        pass "Delete category with reassign"
    else
        fail "Delete category with reassign" "$RESULT"
    fi
fi

# ============================================================================
# SUBSCRIPTIONS
# ============================================================================

echo ""
echo "--- Subscriptions ---"

RESULT=$(settings_curl GET "/-/notifications/subscriptions")
if echo "$RESULT" | python3 -c "import sys, json; json.load(sys.stdin)['data']" 2>/dev/null; then
    pass "List subscriptions"
else
    fail "List subscriptions" "$RESULT"
fi

# ============================================================================
# DESTINATIONS
# ============================================================================

echo ""
echo "--- Destinations ---"

RESULT=$(settings_curl GET "/-/notifications/destinations")
if echo "$RESULT" | python3 -c "
import sys, json
data = json.load(sys.stdin)['data']
sys.exit(0 if 'accounts' in data and 'feeds' in data else 1)" 2>/dev/null; then
    pass "Destinations endpoint returns accounts and feeds"
else
    fail "Destinations endpoint returns accounts and feeds" "$RESULT"
fi

echo ""
echo "=============================================="
echo "Test Results: $PASSED passed, $FAILED failed"
echo "=============================================="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
