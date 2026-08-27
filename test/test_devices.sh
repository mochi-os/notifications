#!/bin/bash
# Copyright © 2026 Mochisoft OÜ
# SPDX-License-Identifier: AGPL-3.0-only
# This file is part of Mochi, licensed under the GNU AGPL v3 with the
# Mochi Application Interface Exception - see license.txt and license-exception.md.

# Devices: the durable record a phone's push accounts hang off. Covers
# registration, binding a push account to the device, one phone staying one
# push target across a transport change with its destination switches carried
# over, and forgetting the device.
# Usage: ./test_devices.sh

set -e

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
NOTIFICATIONS_TOKEN=$(mint_token notifications)
if [ -z "$SETTINGS_TOKEN" ] || [ -z "$NOTIFICATIONS_TOKEN" ]; then
    echo "Could not mint app tokens" >&2
    exit 1
fi

settings_curl() {
    local method="$1"
    local path="$2"
    shift 2
    curl -s -X "$method" -H "Authorization: Bearer $SETTINGS_TOKEN" "$@" \
        "http://localhost:8081/settings$path"
}

# $1 method, $2 path, then curl arguments. Sends the Device header when
# DEVICE_HEADER is set.
notifications_curl() {
    local method="$1"
    local path="$2"
    shift 2
    if [ -n "$DEVICE_HEADER" ]; then
        curl -s -X "$method" -H "Authorization: Bearer $NOTIFICATIONS_TOKEN" -H "Device: $DEVICE_HEADER" "$@" \
            "http://localhost:8081/notifications$path"
    else
        curl -s -X "$method" -H "Authorization: Bearer $NOTIFICATIONS_TOKEN" "$@" \
            "http://localhost:8081/notifications$path"
    fi
}

json_field() {
    python3 -c "
import sys, json
value = json.load(sys.stdin)
for key in sys.argv[1:]:
    value = value[key] if isinstance(value, dict) else value[int(key)]
print(value if not isinstance(value, (list, dict)) else json.dumps(value))" "$@" 2>/dev/null
}

# The account rows carrying $1 as their device, as ids on one line.
accounts_on_device() {
    notifications_curl GET "/-/accounts/list" | DEVICE="$1" python3 -c "
import sys, json, os
rows = json.load(sys.stdin).get('data') or []
print(' '.join(r['id'] for r in rows if r.get('device') == os.environ['DEVICE']))" 2>/dev/null
}

# Exit 0 when category $1 lists account $2 as a destination.
category_has_account() {
    settings_curl GET "/-/notifications/categories" | CATEGORY="$1" ACCOUNT="$2" python3 -c "
import sys, json, os
cats = {c['id']: c for c in json.load(sys.stdin)}
cat = cats.get(os.environ['CATEGORY']) or {'destinations': []}
sys.exit(0 if any(d['type'] == 'account' and d['target'] == os.environ['ACCOUNT'] for d in cat['destinations']) else 1)" 2>/dev/null
}

DEVICE="test-device-0001"

echo "=============================================="
echo "Devices Test Suite"
echo "=============================================="

# Clear what a previous interrupted run left behind.
settings_curl POST "/-/notifications/devices/remove" -d "id=$DEVICE" > /dev/null 2>&1
for stale in $(settings_curl GET "/-/notifications/categories" | python3 -c "
import sys, json
print(' '.join(c['id'] for c in json.load(sys.stdin) if c['label'] == 'DeviceOff'))" 2>/dev/null); do
    settings_curl POST "/-/notifications/categories/delete" -d "id=$stale&reassign=0" > /dev/null 2>&1
done

echo ""
echo "--- Registration ---"

DEVICE_HEADER=""
RESULT=$(notifications_curl POST "/-/device/register" -d "label=Test phone")
if echo "$RESULT" | grep -qE '"error"|Error 400'; then
    pass "Register without a Device header is refused"
else
    fail "Register without a Device header is refused" "$RESULT"
fi

DEVICE_HEADER="bad id!"
RESULT=$(notifications_curl POST "/-/device/register" -d "label=Test phone")
if echo "$RESULT" | grep -qE '"error"|Error 400'; then
    pass "Register with an id outside the alphabet is refused"
else
    fail "Register with an id outside the alphabet is refused" "$RESULT"
fi

DEVICE_HEADER="$DEVICE"
RESULT=$(notifications_curl POST "/-/device/register" -d "label=Test phone")
if [ "$(echo "$RESULT" | json_field data id)" = "$DEVICE" ] && [ "$(echo "$RESULT" | json_field data label)" = "Test phone" ]; then
    pass "Register device"
else
    fail "Register device" "$RESULT"
fi

RESULT=$(notifications_curl POST "/-/device/register" -d "label=Renamed phone")
LISTED=$(settings_curl GET "/-/notifications/devices")
if echo "$LISTED" | DEVICE="$DEVICE" python3 -c "
import sys, json, os
rows = [d for d in json.load(sys.stdin) if d['id'] == os.environ['DEVICE']]
sys.exit(0 if len(rows) == 1 and rows[0]['label'] == 'Renamed phone' else 1)" 2>/dev/null; then
    pass "Re-registration renames the one row, and settings lists it"
else
    fail "Re-registration renames the one row, and settings lists it" "$LISTED"
fi

# Exit 0 when category $1 lists the device surface $2.
category_has_device() {
    settings_curl GET "/-/notifications/categories" | CATEGORY="$1" DEVICE="$2" python3 -c "
import sys, json, os
cats = {c['id']: c for c in json.load(sys.stdin)}
cat = cats.get(os.environ['CATEGORY']) or {'destinations': []}
sys.exit(0 if any(d['type'] == 'device' and d['target'] == os.environ['DEVICE'] for d in cat['destinations']) else 1)" 2>/dev/null
}

if category_has_device "1" "$DEVICE" && ! category_has_device "0" "$DEVICE"; then
    pass "A registered device joins every category but No notifications"
else
    fail "A registered device joins every category but No notifications" "$(settings_curl GET /-/notifications/categories)"
fi

if settings_curl GET "/-/notifications/destinations" | DEVICE="$DEVICE" python3 -c "
import sys, json, os
sys.exit(0 if any(d['id'] == os.environ['DEVICE'] for d in json.load(sys.stdin).get('devices') or []) else 1)" 2>/dev/null; then
    pass "Destinations available lists the device"
else
    fail "Destinations available lists the device" "$(settings_curl GET /-/notifications/destinations)"
fi

echo ""
echo "--- The device surface ---"

CURL_HELPER="/home/alistair/mochi/claude/scripts/curl.sh"
PROBE_TOPIC="device"
PROBE_OBJECT="device-probe"
"$CURL_HELPER" "/test/test_notifications_cleanup?topic=$PROBE_TOPIC&object=$PROBE_OBJECT" > /dev/null 2>&1

# Exit 0 when the probe row is in -/list, with the Device header when
# DEVICE_HEADER is set.
probe_listed() {
    notifications_curl GET "/-/list" | PROBE_TOPIC="$PROBE_TOPIC" PROBE_OBJECT="$PROBE_OBJECT" python3 -c "
import sys, json, os
rows = json.load(sys.stdin).get('data') or []
sys.exit(0 if any(r['topic'] == os.environ['PROBE_TOPIC'] and r['object'] == os.environ['PROBE_OBJECT'] for r in rows) else 1)" 2>/dev/null
}

SURFACE_OFF_ID=$(settings_curl POST "/-/notifications/categories/create" --data-urlencode "label=DeviceSurfaceOff" --data-urlencode 'destinations=[{"type":"web","target":""}]' | json_field id)
"$CURL_HELPER" "/test/test_notifications_emit?topic=$PROBE_TOPIC&object=$PROBE_OBJECT&title=Device%20probe&body=device-probe-body" > /dev/null
PROBE_APP=$(settings_curl GET "/-/notifications/topics" | PROBE_TOPIC="$PROBE_TOPIC" PROBE_OBJECT="$PROBE_OBJECT" python3 -c "
import sys, json, os
rows = json.load(sys.stdin)
match = next((t for t in rows if t['topic'] == os.environ['PROBE_TOPIC'] and t['object'] == os.environ['PROBE_OBJECT']), None)
print(match['app'] if match else '')" 2>/dev/null)

# The probe's topic sits in the default category, which the device joined.
if probe_listed; then
    pass "Device surface on: the device lists the probe"
else
    fail "Device surface on: the device lists the probe" "$(notifications_curl GET /-/list)"
fi

settings_curl POST "/-/notifications/topics/set/category" -d "app=$PROBE_APP&topic=$PROBE_TOPIC&object=$PROBE_OBJECT&category=$SURFACE_OFF_ID" > /dev/null
if ! probe_listed; then
    pass "Device surface off: the device does not list the probe"
else
    fail "Device surface off: the device does not list the probe" "$(notifications_curl GET /-/list)"
fi
COUNTED=$(notifications_curl GET "/-/count")
LISTED=$(notifications_curl GET "/-/list")
if python3 -c "
import sys, json
listed = json.loads(sys.argv[1]); counted = json.loads(sys.argv[2])['data']
sys.exit(0 if listed['count'] == counted['count'] == len([r for r in listed['data'] if r['read'] == 0]) else 1)" "$LISTED" "$COUNTED" 2>/dev/null; then
    pass "Device surface count matches its list"
else
    fail "Device surface count matches its list" "list=$LISTED count=$COUNTED"
fi

SAVED_HEADER="$DEVICE_HEADER"
DEVICE_HEADER=""
if probe_listed; then
    pass "No device: every row, including the probe"
else
    fail "No device: every row, including the probe" "$(notifications_curl GET /-/list)"
fi
DEVICE_HEADER="$SAVED_HEADER"

# The web surface is on for that category, so the browser still sees it.
if notifications_curl GET "/-/list?surface=web" | PROBE_TOPIC="$PROBE_TOPIC" PROBE_OBJECT="$PROBE_OBJECT" python3 -c "
import sys, json, os
rows = json.load(sys.stdin).get('data') or []
sys.exit(0 if any(r['topic'] == os.environ['PROBE_TOPIC'] and r['object'] == os.environ['PROBE_OBJECT'] for r in rows) else 1)" 2>/dev/null; then
    fail "A registered device is its own surface whatever the query asks" "surface=web with a Device header listed the probe"
else
    pass "A registered device is its own surface whatever the query asks"
fi

"$CURL_HELPER" "/test/test_notifications_cleanup?topic=$PROBE_TOPIC&object=$PROBE_OBJECT" > /dev/null 2>&1
settings_curl POST "/-/notifications/categories/delete" -d "id=$SURFACE_OFF_ID&reassign=0" > /dev/null

echo ""
echo "--- Push accounts on the device ---"

RESULT=$(notifications_curl POST "/-/push/register/fcm" -H "Content-Type: application/json" \
    -d "{\"token\":\"fcm-token-1\",\"install_id\":\"install-1\",\"label\":\"Renamed phone\"}")
FCM_ID=$(echo "$RESULT" | json_field data id)
if [ -n "$FCM_ID" ] && [ "$(echo "$RESULT" | json_field data device)" = "$DEVICE" ]; then
    pass "FCM registration binds the account to the device"
else
    fail "FCM registration binds the account to the device" "$RESULT"
fi

# The connected-accounts pages fold a bound account under its device, so the
# settings accounts list must say which device an account belongs to.
RESULT=$(settings_curl GET "/-/accounts/list")
if echo "$RESULT" | FCM_ID="$FCM_ID" DEVICE="$DEVICE" python3 -c "
import sys, json, os
rows = json.load(sys.stdin)
sys.exit(0 if any(r['id'] == os.environ['FCM_ID'] and r.get('device') == os.environ['DEVICE'] for r in rows) else 1)" 2>/dev/null; then
    pass "Settings accounts list carries the account's device"
else
    fail "Settings accounts list carries the account's device" "$RESULT"
fi

# A category created after the FCM account exists does not carry it: that is
# the switch state a transport change must preserve.
OFF_ID=$(settings_curl POST "/-/notifications/categories/create" --data-urlencode "label=DeviceOff" --data-urlencode 'destinations=[]' | json_field id)
if [ -n "$OFF_ID" ] && category_has_account "1" "$FCM_ID" && ! category_has_account "$OFF_ID" "$FCM_ID"; then
    pass "New account joins Normal, and a category made without it stays without it"
else
    fail "New account joins Normal, and a category made without it stays without it" "off=$OFF_ID fcm=$FCM_ID"
fi

RESULT=$(notifications_curl POST "/-/push/register" -d "label=Renamed phone&auth=auth-1&p256dh=p256dh-1&endpoint=")
UP_ID=$(echo "$RESULT" | json_field data id)
if [ -n "$UP_ID" ] && [ "$(echo "$RESULT" | json_field data superseded 0)" = "$FCM_ID" ] && [ "$(accounts_on_device "$DEVICE")" = "$UP_ID" ]; then
    pass "UnifiedPush registration supersedes the FCM account: one push target"
else
    fail "UnifiedPush registration supersedes the FCM account: one push target" "$RESULT / on device: $(accounts_on_device "$DEVICE")"
fi

if category_has_account "1" "$UP_ID" && ! category_has_account "$OFF_ID" "$UP_ID" && ! category_has_account "1" "$FCM_ID"; then
    pass "Destination switches carried across the supersede"
else
    fail "Destination switches carried across the supersede" "$(settings_curl GET /-/notifications/categories)"
fi

RESULT=$(notifications_curl POST "/-/push/register" -d "label=Renamed phone&auth=auth-1&p256dh=p256dh-1&endpoint=/menu/-/push/inbound/$UP_ID")
if [ "$(echo "$RESULT" | json_field data id)" = "$UP_ID" ] && [ "$(accounts_on_device "$DEVICE")" = "$UP_ID" ] && ! category_has_account "$OFF_ID" "$UP_ID"; then
    pass "Re-registering the same endpoint keeps the account and its switches"
else
    fail "Re-registering the same endpoint keeps the account and its switches" "$RESULT"
fi

DEVICE_HEADER="never-registered-0001"
RESULT=$(notifications_curl POST "/-/push/register" -d "label=Stranger&auth=auth-2&p256dh=p256dh-2&endpoint=https://push.example.com/s/2")
STRANGER_ID=$(echo "$RESULT" | json_field data id)
if [ -n "$STRANGER_ID" ] && [ "$(echo "$RESULT" | json_field data device)" = "" ]; then
    pass "An unregistered Device header registers an unbound account"
else
    fail "An unregistered Device header registers an unbound account" "$RESULT"
fi
DEVICE_HEADER="$DEVICE"
notifications_curl POST "/-/accounts/remove" -d "id=$STRANGER_ID" > /dev/null

echo ""
echo "--- Forgetting the device ---"

RESULT=$(settings_curl POST "/-/notifications/devices/remove" -d "id=$DEVICE")
if echo "$RESULT" | grep -q '"ok":true' && [ -z "$(accounts_on_device "$DEVICE")" ] && ! category_has_account "1" "$UP_ID" && ! category_has_device "1" "$DEVICE"; then
    pass "Forgetting the device takes its push account, surface and destination rows"
else
    fail "Forgetting the device takes its push account, surface and destination rows" "$RESULT / on device: $(accounts_on_device "$DEVICE")"
fi

LISTED=$(settings_curl GET "/-/notifications/devices")
if echo "$LISTED" | DEVICE="$DEVICE" python3 -c "
import sys, json, os
sys.exit(1 if any(d['id'] == os.environ['DEVICE'] for d in json.load(sys.stdin)) else 0)" 2>/dev/null; then
    pass "Forgotten device is no longer listed"
else
    fail "Forgotten device is no longer listed" "$LISTED"
fi

RESULT=$(settings_curl POST "/-/notifications/devices/remove" -d "id=$DEVICE")
if echo "$RESULT" | grep -qE '"error"|Error 400'; then
    pass "Forgetting it again is refused"
else
    fail "Forgetting it again is refused" "$RESULT"
fi

settings_curl POST "/-/notifications/categories/delete" -d "id=$OFF_ID&reassign=0" > /dev/null

echo ""
echo "=============================================="
echo "Test Results: $PASSED passed, $FAILED failed"
echo "=============================================="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
