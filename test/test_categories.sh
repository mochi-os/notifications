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

# Clear anything a previous interrupted run left behind, so the assertions
# below describe a category list this run is responsible for.
for stale in $(settings_curl GET "/-/notifications/categories" | python3 -c "
import sys, json
print(' '.join(c['id'] for c in json.load(sys.stdin) if c['label'] in ('TestCat', 'Renamed')))" 2>/dev/null); do
    settings_curl POST "/-/notifications/categories/delete" -d "id=$stale&reassign=0" > /dev/null 2>&1
done

RESULT=$(settings_curl GET "/-/notifications/categories")
if echo "$RESULT" | python3 -c "
import sys, json
cats = json.load(sys.stdin)
ids = {c['id'] for c in cats}
sys.exit(0 if '0' in ids else 1)" 2>/dev/null; then
    pass "'No notifications' (id 0) exists"
else
    fail "'No notifications' (id 0) exists" "$RESULT"
fi

if echo "$RESULT" | python3 -c "
import sys, json
cats = json.load(sys.stdin)
names = {c['label'] for c in cats}
sys.exit(0 if 'Normal' in names else 1)" 2>/dev/null; then
    pass "'Normal' category seeded"
else
    fail "'Normal' category seeded" "$RESULT"
fi

if echo "$RESULT" | python3 -c "
import sys, json
cats = json.load(sys.stdin)
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
NEW_ID=$(echo "$RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "")
if [ -n "$NEW_ID" ]; then
    pass "Create category (id: $NEW_ID)"
else
    fail "Create category" "$RESULT"
fi

if [ -n "$NEW_ID" ]; then
    RESULT=$(settings_curl POST "/-/notifications/categories/update" -d "id=$NEW_ID&label=Renamed")
    CHECK=$(settings_curl GET "/-/notifications/categories")
    if echo "$CHECK" | NEW_ID="$NEW_ID" python3 -c "
import sys, json, os
cats = json.load(sys.stdin)
nid = os.environ['NEW_ID']
match = next((c for c in cats if c['id'] == nid), None)
sys.exit(0 if match and match['label'] == 'Renamed' else 1)" 2>/dev/null; then
        pass "Rename category"
    else
        fail "Rename category" "$CHECK"
    fi
fi

# Delete: must reassign; deleting id 0 must fail
RESULT=$(settings_curl POST "/-/notifications/categories/delete" -d "id=0&reassign_to=1")
if echo "$RESULT" | grep -qE '"error"|Error 4[0-9][0-9]'; then
    pass "Cannot delete 'No notifications' (id 0)"
else
    fail "Cannot delete 'No notifications' (id 0)" "$RESULT"
fi

if [ -n "$NEW_ID" ]; then
    RESULT=$(settings_curl POST "/-/notifications/categories/delete" -d "id=$NEW_ID&reassign=0")
    if echo "$RESULT" | grep -q '"ok":true'; then
        pass "Delete category with reassign"
    else
        fail "Delete category with reassign" "$RESULT"
    fi
fi

# ============================================================================
# SUBSCRIPTIONS
# ============================================================================

echo ""
echo "--- Topics ---"

RESULT=$(settings_curl GET "/-/notifications/topics")
if echo "$RESULT" | python3 -c "import sys, json; sys.exit(0 if isinstance(json.load(sys.stdin), list) else 1)" 2>/dev/null; then
    pass "List topics"
else
    fail "List topics" "$RESULT"
fi

# ============================================================================
# DESTINATIONS
# ============================================================================

echo ""
echo "--- Destinations ---"

RESULT=$(settings_curl GET "/-/notifications/destinations")
if echo "$RESULT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
sys.exit(0 if 'accounts' in data and 'feeds' in data else 1)" 2>/dev/null; then
    pass "Destinations endpoint returns accounts and feeds"
else
    fail "Destinations endpoint returns accounts and feeds" "$RESULT"
fi

# ============================================================================
# SURFACES
# ============================================================================
#
# The web destination is the browser surface: -/list and -/count asked for
# surface=web omit the rows whose topic sits in a category without it, while
# a caller naming no surface (the Android client) sees every row.

echo ""
echo "--- Surfaces ---"

NOTIFICATIONS_TOKEN=$(mint_token notifications)
notifications_curl() {
    local path="$1"
    shift
    curl -s -H "Authorization: Bearer $NOTIFICATIONS_TOKEN" "$@" "http://localhost:8081/notifications$path"
}

PROBE_TOPIC="surface"
PROBE_OBJECT="surface-probe"

# Exit 0 when the probe row is in -/list; $1 is the query string, if any.
probe_listed() {
    notifications_curl "/-/list$1" | PROBE_TOPIC="$PROBE_TOPIC" PROBE_OBJECT="$PROBE_OBJECT" python3 -c "
import sys, json, os
rows = json.load(sys.stdin).get('data') or []
sys.exit(0 if any(r['topic'] == os.environ['PROBE_TOPIC'] and r['object'] == os.environ['PROBE_OBJECT'] for r in rows) else 1)" 2>/dev/null
}

# Exit 0 when the category's test-send row is in -/list; $1 is the query
# string, $2 the category id.
test_row_listed() {
    notifications_curl "/-/list$1" | CATEGORY="$2" python3 -c "
import sys, json, os
rows = json.load(sys.stdin).get('data') or []
sys.exit(0 if any(r['app'] == 'notifications' and r['topic'] == 'test' and r['object'] == os.environ['CATEGORY'] for r in rows) else 1)" 2>/dev/null
}

# Clear a previous interrupted run's probe and categories.
"$CURL_HELPER" "/test/test_notifications_cleanup?topic=$PROBE_TOPIC&object=$PROBE_OBJECT" > /dev/null 2>&1
for stale in $(settings_curl GET "/-/notifications/categories" | python3 -c "
import sys, json
print(' '.join(c['id'] for c in json.load(sys.stdin) if c['label'] in ('SurfaceOn', 'SurfaceOff')))" 2>/dev/null); do
    settings_curl POST "/-/notifications/categories/delete" -d "id=$stale&reassign=0" > /dev/null 2>&1
done

ON_ID=$(settings_curl POST "/-/notifications/categories/create" --data-urlencode "label=SurfaceOn" --data-urlencode 'destinations=[{"type":"web","target":""}]' | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "")
OFF_ID=$(settings_curl POST "/-/notifications/categories/create" --data-urlencode "label=SurfaceOff" --data-urlencode 'destinations=[]' | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "")
RESULT=$(settings_curl GET "/-/notifications/categories")
if echo "$RESULT" | ON_ID="$ON_ID" OFF_ID="$OFF_ID" python3 -c "
import sys, json, os
cats = {c['id']: c for c in json.load(sys.stdin)}
on = cats.get(os.environ['ON_ID'])
off = cats.get(os.environ['OFF_ID'])
ok = on and off and [d['type'] for d in on['destinations']] == ['web'] and off['destinations'] == []
sys.exit(0 if ok else 1)" 2>/dev/null; then
    pass "Create categories with the web surface on and off"
else
    fail "Create categories with the web surface on and off" "$RESULT"
fi

# A real send through the routing pipeline; the topic is created with the
# default category, then moved.
RESULT=$("$CURL_HELPER" "/test/test_notifications_emit?topic=$PROBE_TOPIC&object=$PROBE_OBJECT&title=Surface%20probe&body=surface-probe-body")
if echo "$RESULT" | grep -q '"sent":1'; then
    pass "Emit surface probe"
else
    fail "Emit surface probe" "$RESULT"
fi

PROBE_APP=$(settings_curl GET "/-/notifications/topics" | PROBE_TOPIC="$PROBE_TOPIC" PROBE_OBJECT="$PROBE_OBJECT" python3 -c "
import sys, json, os
rows = json.load(sys.stdin)
match = next((t for t in rows if t['topic'] == os.environ['PROBE_TOPIC'] and t['object'] == os.environ['PROBE_OBJECT']), None)
print(match['app'] if match else '')" 2>/dev/null)

settings_curl POST "/-/notifications/topics/set/category" -d "app=$PROBE_APP&topic=$PROBE_TOPIC&object=$PROBE_OBJECT&category=$OFF_ID" > /dev/null
if probe_listed ""; then
    pass "Web surface off: listed when no surface is named"
else
    fail "Web surface off: listed when no surface is named" "$(notifications_curl /-/list)"
fi
if probe_listed "?surface=web"; then
    fail "Web surface off: hidden from surface=web" "$(notifications_curl '/-/list?surface=web')"
else
    pass "Web surface off: hidden from surface=web"
fi

# The count must agree with the list it accompanies, and the unfiltered
# count must carry at least the unread probe the web surface does not.
LISTED=$(notifications_curl "/-/list?surface=web")
COUNTED=$(notifications_curl "/-/count?surface=web")
COUNTED_ALL=$(notifications_curl "/-/count")
if python3 -c "
import sys, json
listed = json.loads(sys.argv[1]); counted = json.loads(sys.argv[2])['data']; everything = json.loads(sys.argv[3])['data']
unread = [r for r in listed['data'] if r['read'] == 0]
sys.exit(0 if listed['count'] == counted['count'] == len(unread) and everything['count'] >= counted['count'] + 1 else 1)" "$LISTED" "$COUNTED" "$COUNTED_ALL" 2>/dev/null; then
    pass "Web surface count matches its list"
else
    fail "Web surface count matches its list" "list=$LISTED count=$COUNTED all=$COUNTED_ALL"
fi

settings_curl POST "/-/notifications/topics/set/category" -d "app=$PROBE_APP&topic=$PROBE_TOPIC&object=$PROBE_OBJECT&category=$ON_ID" > /dev/null
if probe_listed "?surface=web"; then
    pass "Web surface on: listed on surface=web"
else
    fail "Web surface on: listed on surface=web" "$(notifications_curl '/-/list?surface=web')"
fi

# The test send writes its bell entry only when the surface is on.
RESULT=$(settings_curl POST "/-/notifications/categories/test" -d "id=$OFF_ID")
if echo "$RESULT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
sys.exit(0 if d.get('web') is False and d.get('sent') == 0 else 1)" 2>/dev/null && ! test_row_listed "" "$OFF_ID"; then
    pass "Test send with the web surface off writes no bell entry"
else
    fail "Test send with the web surface off writes no bell entry" "$RESULT"
fi
RESULT=$(settings_curl POST "/-/notifications/categories/test" -d "id=$ON_ID")
if echo "$RESULT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
sys.exit(0 if d.get('web') is True and d.get('sent') >= 1 else 1)" 2>/dev/null && test_row_listed "?surface=web" "$ON_ID"; then
    pass "Test send with the web surface on writes a bell entry"
else
    fail "Test send with the web surface on writes a bell entry" "$RESULT"
fi

# Clean up: the probe and its topic, the bell entry the test send wrote,
# then the categories.
"$CURL_HELPER" "/test/test_notifications_cleanup?topic=$PROBE_TOPIC&object=$PROBE_OBJECT" > /dev/null 2>&1
TEST_ROW=$(notifications_curl "/-/list" | CATEGORY="$ON_ID" python3 -c "
import sys, json, os
rows = json.load(sys.stdin).get('data') or []
print(next((r['id'] for r in rows if r['app'] == 'notifications' and r['topic'] == 'test' and r['object'] == os.environ['CATEGORY']), ''))" 2>/dev/null)
if [ -n "$TEST_ROW" ]; then
    notifications_curl "/-/read" -d "id=$TEST_ROW" > /dev/null
fi
settings_curl POST "/-/notifications/categories/delete" -d "id=$ON_ID&reassign=0" > /dev/null
settings_curl POST "/-/notifications/categories/delete" -d "id=$OFF_ID&reassign=0" > /dev/null

echo ""
echo "=============================================="
echo "Test Results: $PASSED passed, $FAILED failed"
echo "=============================================="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
