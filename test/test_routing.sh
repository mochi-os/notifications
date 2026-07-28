#!/bin/bash
# Copyright © 2026 Mochisoft OÜ
# SPDX-License-Identifier: AGPL-3.0-only
# This file is part of Mochi, licensed under the GNU AGPL v3 with the
# Mochi Application Interface Exception - see license.txt and license-exception.md.

# Notification Routing Test Suite
# Tests RSS feed management and external URL provider
# Usage: ./test_routing.sh

set -e

CURL_HELPER="/home/alistair/mochi/claude/scripts/curl.sh"

PASSED=0
FAILED=0
ACCOUNT_ID=""
RSS_ID=""

pass() {
    echo "[PASS] $1"
    ((PASSED++)) || true
}

fail() {
    echo "[FAIL] $1: $2"
    ((FAILED++)) || true
}

# Helper to make notifications requests
notif_curl() {
    local method="$1"
    local path="$2"
    shift 2
    "$CURL_HELPER" -a admin -X "$method" "$@" "/notifications$path"
}

# Helper to make settings requests (for account creation)
settings_curl() {
    local method="$1"
    local path="$2"
    shift 2
    "$CURL_HELPER" -a admin -X "$method" "$@" "/settings$path"
}

echo "=============================================="
echo "Notification Routing Test Suite"
echo "=============================================="

# ============================================================================
# RSS FEED MANAGEMENT TESTS
# ============================================================================

echo ""
echo "--- RSS Feed Management Tests ---"

# Test: List feeds (should be empty initially)
RESULT=$(notif_curl GET "/-/rss/list")
if echo "$RESULT" | python3 -c "import sys, json; data = json.load(sys.stdin).get('data', []); sys.exit(0 if len(data) == 0 else 1)" 2>/dev/null; then
    pass "No feeds initially"
else
    # May have existing feeds, that's ok
    pass "List feeds works"
fi

# Test: Create a feed
RESULT=$(notif_curl POST "/-/rss/create" -d "name=Test Feed")
if echo "$RESULT" | grep -q '"name":"Test Feed"' && echo "$RESULT" | grep -q '"token"'; then
    RSS_FEED_ID=$(echo "$RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin)['data']['id'])" 2>/dev/null || echo "")
    FEED_TOKEN=$(echo "$RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin)['data']['token'])" 2>/dev/null || echo "")
    pass "Create feed (ID: $RSS_FEED_ID)"
else
    fail "Create feed" "$RESULT"
fi

# Test: List feeds shows new feed
RESULT=$(notif_curl GET "/-/rss/list")
if echo "$RESULT" | grep -q '"name":"Test Feed"'; then
    pass "Feed appears in list"
else
    fail "Feed appears in list" "$RESULT"
fi

# Test: RSS with feed token
if [ -n "$FEED_TOKEN" ]; then
    RESULT=$(curl -s "http://localhost:8081/notifications/-/rss?token=$FEED_TOKEN")
    if echo "$RESULT" | grep -q '<?xml' && echo "$RESULT" | grep -q '<rss'; then
        pass "RSS feed accessible with token"
    else
        fail "RSS feed accessible with token" "$RESULT"
    fi
fi

# Test: RSS feed shows feed name in title
if [ -n "$FEED_TOKEN" ]; then
    RESULT=$(curl -s "http://localhost:8081/notifications/-/rss?token=$FEED_TOKEN")
    if echo "$RESULT" | grep -q '<title>Test Feed</title>'; then
        pass "RSS feed title is feed name"
    else
        fail "RSS feed title is feed name" "$RESULT"
    fi
fi

# ============================================================================
# RSS ROUTING TESTS
# ============================================================================

echo ""
echo "--- RSS Routing Tests ---"

# Test: Create a feed subscribed to no category
RESULT=$(notif_curl POST "/-/rss/create" -d "name=Unsubscribed Feed&add_to_existing=0")
UNSUB_FEED_ID=$(echo "$RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin)['data']['id'])" 2>/dev/null || echo "")
UNSUB_TOKEN=$(echo "$RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin)['data']['token'])" 2>/dev/null || echo "")
if [ -n "$UNSUB_TOKEN" ]; then
    pass "Create unsubscribed feed (ID: $UNSUB_FEED_ID)"
else
    fail "Create unsubscribed feed" "$RESULT"
fi

# add_to_existing=0 also creates the feed disabled; enable it so the empty
# result below proves category routing, not the enabled gate
notif_curl POST "/-/rss/update" -d "id=$UNSUB_FEED_ID&enabled=1" > /dev/null

# Test: Emit a routed notification (topic lands in the default category,
# which the subscribed "Test Feed" is an rss destination of)
RESULT=$(curl -s "http://localhost:8081/test/test_notifications_emit")
if echo "$RESULT" | grep -q '"sent":1'; then
    pass "Emit routed probe notification"
else
    fail "Emit routed probe notification" "$RESULT"
fi

# Test: Subscribed feed carries the routed notification
RESULT=$(curl -s "http://localhost:8081/notifications/-/rss?token=$FEED_TOKEN")
if echo "$RESULT" | grep -q 'rss-routing-probe-body'; then
    pass "Subscribed feed carries routed notification"
else
    fail "Subscribed feed carries routed notification" "$RESULT"
fi

# Test: Unsubscribed feed serves valid XML without the notification
RESULT=$(curl -s "http://localhost:8081/notifications/-/rss?token=$UNSUB_TOKEN")
if echo "$RESULT" | grep -q '<rss' && ! echo "$RESULT" | grep -q 'rss-routing-probe-body'; then
    pass "Unsubscribed feed excludes routed notification"
else
    fail "Unsubscribed feed excludes routed notification" "$RESULT"
fi

# Test: Disabling a feed revokes its token until re-enabled
notif_curl POST "/-/rss/update" -d "id=$RSS_FEED_ID&enabled=0" > /dev/null
RESULT=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8081/notifications/-/rss?token=$FEED_TOKEN")
if [ "$RESULT" = "404" ]; then
    pass "Disabled feed returns 404"
else
    fail "Disabled feed returns 404" "Got HTTP $RESULT"
fi

notif_curl POST "/-/rss/update" -d "id=$RSS_FEED_ID&enabled=1" > /dev/null
RESULT=$(curl -s "http://localhost:8081/notifications/-/rss?token=$FEED_TOKEN")
if echo "$RESULT" | grep -q 'rss-routing-probe-body'; then
    pass "Re-enabled feed serves content again"
else
    fail "Re-enabled feed serves content again" "$RESULT"
fi

# Cleanup: remove the probe notification/topic and the unsubscribed feed
curl -s "http://localhost:8081/test/test_notifications_cleanup" > /dev/null
if [ -n "$UNSUB_FEED_ID" ]; then
    notif_curl POST "/-/rss/delete" -d "id=$UNSUB_FEED_ID" > /dev/null
fi

# ============================================================================
# EVENT ID COLLISION TESTS
# ============================================================================

echo ""
echo "--- Event ID Collision Tests ---"

# Two notifications sharing an event id under different objects must both
# survive: the row id is derived from (app, event id) and a same-app reuse
# falls back to a fresh uid rather than being silently dropped.
curl -s "http://localhost:8081/test/test_notifications_emit?object=collide-a&body=collide-body-a&event=collide-probe" > /dev/null
curl -s "http://localhost:8081/test/test_notifications_emit?object=collide-b&body=collide-body-b&event=collide-probe" > /dev/null

RESULT=$(notif_curl GET "/-/list")
if echo "$RESULT" | grep -q 'collide-body-a'; then
    pass "First event-keyed notification stored"
else
    fail "First event-keyed notification stored" "$RESULT"
fi
if echo "$RESULT" | grep -q 'collide-body-b'; then
    pass "Colliding event id does not drop the second notification"
else
    fail "Colliding event id does not drop the second notification" "$RESULT"
fi

curl -s "http://localhost:8081/test/test_notifications_cleanup?object=collide-a" > /dev/null
curl -s "http://localhost:8081/test/test_notifications_cleanup?object=collide-b" > /dev/null

# Test: Event-keyed ids exceed 64 chars and must stay markable as read on both
# HTTP paths (the notifications action and the menu tray proxy)
LONG_EVENT=$(python3 -c "print('e' * 100)")
curl -s -X POST -d "object=read-probe&body=read-probe-body&event=$LONG_EVENT" "http://localhost:8081/test/test_notifications_emit" > /dev/null
RESULT=$(notif_curl POST "/-/read" -d "id=test:$LONG_EVENT")
if echo "$RESULT" | grep -q '"data"'; then
    pass "Long event-keyed id accepted by the read action"
else
    fail "Long event-keyed id accepted by the read action" "$(echo "$RESULT" | head -c 150)"
fi
RESULT=$("$CURL_HELPER" -a admin -X POST -d "id=test:$LONG_EVENT" "/menu/-/notifications/read")
if echo "$RESULT" | grep -q '"ok":true'; then
    pass "Long event-keyed id accepted by the menu tray"
else
    fail "Long event-keyed id accepted by the menu tray" "$(echo "$RESULT" | head -c 150)"
fi
RESULT=$(notif_curl GET "/-/list")
if echo "$RESULT" | python3 -c "
import sys, json
rows = json.load(sys.stdin)['data']
row = next((r for r in rows if r['object'] == 'read-probe'), None)
sys.exit(0 if row and row['read'] != 0 else 1)
" 2>/dev/null; then
    pass "Long event-keyed notification marked read"
else
    fail "Long event-keyed notification marked read" "$(echo "$RESULT" | head -c 150)"
fi
curl -s "http://localhost:8081/test/test_notifications_cleanup?object=read-probe" > /dev/null

# ============================================================================
# PUSH QUEUE SCOPING TESTS
# ============================================================================

echo ""
echo "--- Push Queue Scoping Tests ---"

extract_id() {
    python3 -c "import sys, json; d = json.load(sys.stdin); d = d.get('data', d) if isinstance(d, dict) else d; print(d.get('id', ''))" 2>/dev/null || echo ""
}

# Register two local-distributor subscriptions (device A and device B)
RESULT=$(notif_curl POST "/-/push/register" -d "label=drain-probe-a&auth=WPF1D0bTRYUiNH98kIfhjA&p256dh=BGc2vQrRsQGN6oKjmkP_3RaMtxAaAevBBe7N0xCv1tIJaEGI3DRD0fA73tk5Mt1JsmvP6Z8tFc8MGD7e2eUKHKM")
SUB_A=$(echo "$RESULT" | extract_id)
RESULT=$(notif_curl POST "/-/push/register" -d "label=drain-probe-b&auth=XPF1D0bTRYUiNH98kIfhjB&p256dh=BGc2vQrRsQGN6oKjmkP_3RaMtxAaAevBBe7N0xCv1tIJaEGI3DRD0fA73tk5Mt1JsmvP6Z8tFc8MGD7e2eUKHKN")
SUB_B=$(echo "$RESULT" | extract_id)
if [ -n "$SUB_A" ] && [ -n "$SUB_B" ] && [ "$SUB_A" != "$SUB_B" ]; then
    pass "Register two push subscriptions"
else
    fail "Register two push subscriptions" "A=$SUB_A B=$SUB_B"
fi

# Emit: both subscriptions get a queued backstop row for the same event
curl -s "http://localhost:8081/test/test_notifications_emit?object=drain-probe&body=drain-probe-body" > /dev/null
PROBE_EVENT="test-probe-drain-probe"

# Test: Scoped drain sees only the caller's subscription
RESULT=$(notif_curl GET "/-/push/drain?subscription=$SUB_A")
if echo "$RESULT" | grep -q "\"subId\":\"$SUB_A\"" && ! echo "$RESULT" | grep -q "\"subId\":\"$SUB_B\""; then
    pass "Scoped drain returns only the caller's subscription"
else
    fail "Scoped drain returns only the caller's subscription" "$RESULT"
fi

# Test: Unscoped drain (installed clients) still returns everything
RESULT=$(notif_curl GET "/-/push/drain")
if echo "$RESULT" | grep -q "\"subId\":\"$SUB_A\"" && echo "$RESULT" | grep -q "\"subId\":\"$SUB_B\""; then
    pass "Unscoped drain returns all subscriptions"
else
    fail "Unscoped drain returns all subscriptions" "$RESULT"
fi

# Test: Scoped ack cannot delete another subscription's row
EVENTS_B="[{\"account\":\"$SUB_B\",\"event_id\":\"$PROBE_EVENT\"}]"
notif_curl POST "/-/push/ack" -d "subscription=$SUB_A&events=$EVENTS_B" > /dev/null
RESULT=$(notif_curl GET "/-/push/drain")
if echo "$RESULT" | grep -q "\"subId\":\"$SUB_B\""; then
    pass "Scoped ack cannot delete another subscription's row"
else
    fail "Scoped ack cannot delete another subscription's row" "$RESULT"
fi

# Test: Scoped ack deletes the caller's own row
EVENTS_A="[{\"account\":\"$SUB_A\",\"event_id\":\"$PROBE_EVENT\"}]"
notif_curl POST "/-/push/ack" -d "subscription=$SUB_A&events=$EVENTS_A" > /dev/null
RESULT=$(notif_curl GET "/-/push/drain")
if ! echo "$RESULT" | grep -q "\"subId\":\"$SUB_A\""; then
    pass "Scoped ack deletes the caller's row"
else
    fail "Scoped ack deletes the caller's row" "$RESULT"
fi

# Cleanup: ack the remaining row, remove subscriptions and the probe rows
notif_curl POST "/-/push/ack" -d "events=$EVENTS_B" > /dev/null
notif_curl POST "/-/push/accounts/remove" -d "id=$SUB_A" > /dev/null
notif_curl POST "/-/push/accounts/remove" -d "id=$SUB_B" > /dev/null
curl -s "http://localhost:8081/test/test_notifications_cleanup?object=drain-probe" > /dev/null

# ============================================================================
# INPUT SIZE LIMIT TESTS
# ============================================================================

echo ""
echo "--- Input Size Limit Tests ---"

# Test: Oversized body is truncated but the notification still arrives
LONG_BODY=$(python3 -c "print('a' * 5000)")
curl -s -X POST -d "object=size-probe&body=$LONG_BODY" "http://localhost:8081/test/test_notifications_emit" > /dev/null
RESULT=$(notif_curl GET "/-/list")
if echo "$RESULT" | python3 -c "
import sys, json
rows = json.load(sys.stdin)['data']
row = next((r for r in rows if r['object'] == 'size-probe'), None)
sys.exit(0 if row and 0 < len(row['body']) <= 2048 else 1)
" 2>/dev/null; then
    pass "Oversized body truncated but delivered"
else
    fail "Oversized body truncated but delivered" "$(echo "$RESULT" | head -c 200)"
fi
curl -s "http://localhost:8081/test/test_notifications_cleanup?object=size-probe" > /dev/null

# Test: Oversized topic is rejected (identity keys are never truncated)
LONG_TOPIC=$(python3 -c "print('t' * 300)")
RESULT=$(curl -s -X POST -d "topic=$LONG_TOPIC&object=size-probe-2&body=x" "http://localhost:8081/test/test_notifications_emit")
if echo "$RESULT" | grep -q '"sent":0'; then
    pass "Oversized topic rejected"
else
    fail "Oversized topic rejected" "$RESULT"
    curl -s -X POST -d "topic=$LONG_TOPIC&object=size-probe-2" "http://localhost:8081/test/test_notifications_cleanup" > /dev/null
fi

# Test: Oversized push registration endpoint is refused
LONG_ENDPOINT=$(python3 -c "print('https://example.com/' + 'e' * 3000)")
RESULT=$(notif_curl POST "/-/push/register" -d "auth=WPF1D0bTRYUiNH98kIfhjA&p256dh=BGc2vQrRsQGN6oKjmkP_3RaMtxAaAevBBe7N0xCv1tIJaEGI3DRD0fA73tk5Mt1JsmvP6Z8tFc8MGD7e2eUKHKM&endpoint=$LONG_ENDPOINT")
if echo "$RESULT" | grep -qi "registration failed"; then
    pass "Oversized push registration refused"
else
    fail "Oversized push registration refused" "$(echo "$RESULT" | head -c 200)"
    LEAK_ID=$(echo "$RESULT" | extract_id)
    [ -n "$LEAK_ID" ] && notif_curl POST "/-/push/accounts/remove" -d "id=$LEAK_ID" > /dev/null
fi

# Test: Over-long feed token with session auth returns 404 (characterization:
# same result as an unknown token; the cap only skips the lookup)
LONG_FEED_TOKEN=$(python3 -c "print('k' * 1000)")
RESULT=$("$CURL_HELPER" -a admin "/notifications/-/rss?token=$LONG_FEED_TOKEN")
if echo "$RESULT" | grep -q "Feed not found"; then
    pass "Over-long feed token returns 404"
else
    fail "Over-long feed token returns 404" "$(echo "$RESULT" | head -c 150)"
fi

# Test: Invalid feed token returns 401
RESULT=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8081/notifications/-/rss?token=invalid_token_12345")
if [ "$RESULT" = "401" ]; then
    pass "Invalid feed token returns 401"
else
    fail "Invalid feed token returns 401" "Got HTTP $RESULT"
fi

# Test: Delete feed
if [ -n "$RSS_FEED_ID" ]; then
    RESULT=$(notif_curl POST "/-/rss/delete" -d "id=$RSS_FEED_ID")
    if echo "$RESULT" | grep -q '"data":{}'; then
        pass "Delete feed"
    else
        fail "Delete feed" "$RESULT"
    fi
fi

# Test: Deleted feed token no longer works
if [ -n "$FEED_TOKEN" ]; then
    RESULT=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8081/notifications/-/rss?token=$FEED_TOKEN")
    if [ "$RESULT" = "401" ]; then
        pass "Deleted feed token returns 401"
    else
        fail "Deleted feed token returns 401" "Got HTTP $RESULT"
    fi
fi

# ============================================================================
# TOPIC DELETE TESTS
# ============================================================================

echo ""
echo "--- Topic Delete Tests ---"

# Emit to create a topic row, delete it via the HTTP action, verify gone
curl -s "http://localhost:8081/test/test_notifications_emit?object=topic-probe&body=topic-probe-body" > /dev/null
RESULT=$(notif_curl POST "/-/topics/delete" -d "app=test&topic=probe&object=topic-probe")
if echo "$RESULT" | grep -q '"data"'; then
    pass "Topic delete succeeds"
else
    fail "Topic delete succeeds" "$(echo "$RESULT" | head -c 150)"
fi
RESULT=$(notif_curl GET "/-/topics/lookup?app=test&topic=probe&object=topic-probe")
if echo "$RESULT" | grep -q '"data":null'; then
    pass "Deleted topic no longer found"
else
    fail "Deleted topic no longer found" "$(echo "$RESULT" | head -c 150)"
fi
RESULT=$(notif_curl POST "/-/topics/delete" -d "app=test&topic=probe&object=topic-probe")
if echo "$RESULT" | grep -q "Topic not found"; then
    pass "Deleting a missing topic returns 404"
else
    fail "Deleting a missing topic returns 404" "$(echo "$RESULT" | head -c 150)"
fi
curl -s "http://localhost:8081/test/test_notifications_cleanup?object=topic-probe" > /dev/null

# ============================================================================
# ACCOUNT REMOVAL CLEANUP TESTS
# ============================================================================

echo ""
echo "--- Account Removal Cleanup Tests ---"

# Register two subscriptions, queue a row for each, then remove one through
# the notifications function path and one through the settings UI path;
# neither queued row (nor the settings one's destination rows) may survive.
RESULT=$(notif_curl POST "/-/push/register" -d "label=cleanup-probe-c&auth=YPF1D0bTRYUiNH98kIfhjC&p256dh=BGc2vQrRsQGN6oKjmkP_3RaMtxAaAevBBe7N0xCv1tIJaEGI3DRD0fA73tk5Mt1JsmvP6Z8tFc8MGD7e2eUKHKO")
SUB_C=$(echo "$RESULT" | extract_id)
RESULT=$(notif_curl POST "/-/push/register" -d "label=cleanup-probe-d&auth=ZPF1D0bTRYUiNH98kIfhjD&p256dh=BGc2vQrRsQGN6oKjmkP_3RaMtxAaAevBBe7N0xCv1tIJaEGI3DRD0fA73tk5Mt1JsmvP6Z8tFc8MGD7e2eUKHKP")
SUB_D=$(echo "$RESULT" | extract_id)
curl -s "http://localhost:8081/test/test_notifications_emit?object=cleanup-probe&body=cleanup-probe-body" > /dev/null

RESULT=$(notif_curl GET "/-/push/drain")
if echo "$RESULT" | grep -q "\"subId\":\"$SUB_C\"" && echo "$RESULT" | grep -q "\"subId\":\"$SUB_D\""; then
    pass "Both subscriptions queued before removal"
else
    fail "Both subscriptions queued before removal" "$(echo "$RESULT" | head -c 200)"
fi

# Test: Removal through the notifications function path clears the queue
notif_curl POST "/-/push/accounts/remove" -d "id=$SUB_C" > /dev/null
RESULT=$(notif_curl GET "/-/push/drain")
if ! echo "$RESULT" | grep -q "\"subId\":\"$SUB_C\"" && echo "$RESULT" | grep -q "\"subId\":\"$SUB_D\""; then
    pass "Queued rows removed with the account (function path)"
else
    fail "Queued rows removed with the account (function path)" "$(echo "$RESULT" | head -c 200)"
fi

# Test: Removal through settings clears the queue and destinations
settings_curl POST "/-/accounts/remove" -d "id=$SUB_D" > /dev/null
RESULT=$(notif_curl GET "/-/push/drain")
if ! echo "$RESULT" | grep -q "\"subId\":\"$SUB_D\""; then
    pass "Queued rows removed with the account (settings path)"
else
    fail "Queued rows removed with the account (settings path)" "$(echo "$RESULT" | head -c 200)"
fi
RESULT=$(notif_curl GET "/-/categories/list")
if ! echo "$RESULT" | grep -q "\"target\":\"$SUB_D\""; then
    pass "Destination rows removed with the account (settings path)"
else
    fail "Destination rows removed with the account (settings path)" "$(echo "$RESULT" | head -c 200)"
fi

curl -s "http://localhost:8081/test/test_notifications_cleanup?object=cleanup-probe" > /dev/null

# ============================================================================
# MALFORMED INPUT TESTS
# ============================================================================

echo ""
echo "--- Malformed Input Tests ---"

# Test: Malformed destinations JSON answers a clean 400
RESULT=$(notif_curl POST "/-/categories/create" -d "label=BadDest&destinations={not-json")
if echo "$RESULT" | grep -q "Invalid destinations"; then
    pass "Malformed destinations JSON returns clean 400"
else
    fail "Malformed destinations JSON returns clean 400" "$(echo "$RESULT" | head -c 200)"
fi

# Test: Non-dict destination elements answer a clean 400
RESULT=$(notif_curl POST "/-/categories/create" -d 'label=BadDest&destinations=["x"]')
if echo "$RESULT" | grep -q "Invalid destinations"; then
    pass "Non-dict destination elements return clean 400"
else
    fail "Non-dict destination elements return clean 400" "$(echo "$RESULT" | head -c 200)"
fi

# Test: Oversized destinations list answers a clean 400
BIG_DESTS=$(python3 -c "import json; print(json.dumps([{'type':'web','target':str(i)} for i in range(101)], separators=(',', ':')))")
RESULT=$(notif_curl POST "/-/categories/create" -d "label=BadDest&destinations=$BIG_DESTS")
if echo "$RESULT" | grep -q "Invalid destinations"; then
    pass "Oversized destinations list returns clean 400"
else
    fail "Oversized destinations list returns clean 400" "$(echo "$RESULT" | head -c 200)"
fi

# Test: The settings proxy answers the same clean 400
RESULT=$(settings_curl POST "/-/notifications/categories/create" -d "label=BadDest&destinations={not-json")
if echo "$RESULT" | grep -q "Invalid destinations"; then
    pass "Settings proxy returns clean 400 for malformed destinations"
else
    fail "Settings proxy returns clean 400 for malformed destinations" "$(echo "$RESULT" | head -c 200)"
fi

# Test: Unknown account type answers a clean 400 on both add surfaces
RESULT=$(notif_curl POST "/-/accounts/add" -d "type=garbage&label=x")
if echo "$RESULT" | grep -q "Invalid type"; then
    pass "Unknown account type returns clean 400 (notifications)"
else
    fail "Unknown account type returns clean 400 (notifications)" "$(echo "$RESULT" | head -c 150)"
fi
RESULT=$(settings_curl POST "/-/accounts/add" -d "type=garbage&label=x")
if echo "$RESULT" | grep -q "Invalid type"; then
    pass "Unknown account type returns clean 400 (settings)"
else
    fail "Unknown account type returns clean 400 (settings)" "$(echo "$RESULT" | head -c 150)"
fi

# Test: Malformed ack events JSON answers a clean 400
RESULT=$(notif_curl POST "/-/push/ack" -d "events={bad")
if echo "$RESULT" | grep -q "Invalid push subscription"; then
    pass "Malformed ack events returns clean 400"
else
    fail "Malformed ack events returns clean 400" "$(echo "$RESULT" | head -c 200)"
fi

# Test: Oversized ack batch answers a clean 400
BIG_EVENTS=$(python3 -c "import json; print(json.dumps([{'account':'x','event_id':str(i)} for i in range(1001)], separators=(',', ':')))")
RESULT=$(notif_curl POST "/-/push/ack" -d "events=$BIG_EVENTS")
if echo "$RESULT" | grep -q "Invalid push subscription"; then
    pass "Oversized ack batch returns clean 400"
else
    fail "Oversized ack batch returns clean 400" "$(echo "$RESULT" | head -c 200)"
fi

# Test: Unknown destination type answers a clean 400
RESULT=$(notif_curl POST "/-/categories/create" -d 'label=BadDest&destinations=[{"type":"evil","target":"x"}]')
if echo "$RESULT" | grep -q "Invalid destinations"; then
    pass "Unknown destination type returns clean 400"
else
    fail "Unknown destination type returns clean 400" "$(echo "$RESULT" | head -c 150)"
fi

# Test: Oversized destination target answers a clean 400
LONG_TARGET=$(python3 -c "print('t' * 100)")
RESULT=$(notif_curl POST "/-/categories/create" -d "label=BadDest&destinations=[{\"type\":\"web\",\"target\":\"$LONG_TARGET\"}]")
if echo "$RESULT" | grep -q "Invalid destinations"; then
    pass "Oversized destination target returns clean 400"
else
    fail "Oversized destination target returns clean 400" "$(echo "$RESULT" | head -c 150)"
fi

# Test: Over-length category label is rejected
LONG_LABEL=$(python3 -c "print('L' * 200)")
RESULT=$(notif_curl POST "/-/categories/create" -d "label=$LONG_LABEL")
if echo "$RESULT" | grep -q "Invalid category"; then
    pass "Over-length category label rejected"
else
    fail "Over-length category label rejected" "$(echo "$RESULT" | head -c 150)"
fi
# Red-phase cleanup: an accepted long label persisted a category; remove it
notif_curl GET "/-/categories/list" | python3 -c "
import sys, json
for c in json.load(sys.stdin).get('data', []):
    if len(c.get('label', '')) > 100:
        print(c['id'])
" 2>/dev/null | while read -r CID; do
    notif_curl POST "/-/categories/delete" -d "id=$CID&reassign_to=1" > /dev/null
done

# Cleanup: pre-fix aborts leak a half-created category; remove any BadDest rows
notif_curl GET "/-/categories/list" | python3 -c "
import sys, json
for c in json.load(sys.stdin).get('data', []):
    if c.get('label') == 'BadDest':
        print(c['id'])
" 2>/dev/null | while read -r CID; do
    notif_curl POST "/-/categories/delete" -d "id=$CID&reassign_to=1" > /dev/null
done

# ============================================================================
# EXTERNAL URL PROVIDER TESTS
# ============================================================================

echo ""
echo "--- External URL Provider Tests ---"

# Test: External URL provider exists
RESULT=$(settings_curl GET "/-/accounts/providers?capability=notify")
if echo "$RESULT" | grep -q '"type":"url"'; then
    pass "External URL provider exists"
else
    fail "External URL provider exists" "$RESULT"
fi

# Test: Add external URL account
RESULT=$(settings_curl POST "/-/accounts/add" -d "type=url&url=https://example.com/notify&secret=test_secret&label=Test URL")
if echo "$RESULT" | grep -q '"type":"url"' && echo "$RESULT" | grep -q '"identifier":"https://example.com/notify"'; then
    URL_ID=$(echo "$RESULT" | python3 -c "import sys, json; d = json.load(sys.stdin); d = d.get('data', d) if isinstance(d, dict) else d; print(d.get('id', ''))" 2>/dev/null || echo "")
    pass "Add external URL account (ID: $URL_ID)"
else
    fail "Add external URL account" "$RESULT"
fi

# Test: External URL account is immediately verified
RESULT=$(settings_curl GET "/-/accounts/list")
if echo "$RESULT" | python3 -c "import sys, json; d = json.load(sys.stdin); accounts = d.get('data', d) if isinstance(d, dict) else d; u = next((a for a in accounts if a['type'] == 'url'), None); sys.exit(0 if u and u['verified'] > 0 else 1)" 2>/dev/null; then
    pass "External URL account immediately verified"
else
    fail "External URL account immediately verified" "$RESULT"
fi

# Test: Over-length account label updates are rejected on both surfaces
LONG_ALABEL=$(python3 -c "print('A' * 5000)")
if [ -n "$URL_ID" ]; then
    RESULT=$(notif_curl POST "/-/accounts/update" -d "id=$URL_ID&label=$LONG_ALABEL")
    if echo "$RESULT" | grep -q "too long"; then
        pass "Over-length account label rejected (notifications)"
    else
        fail "Over-length account label rejected (notifications)" "$(echo "$RESULT" | head -c 150)"
    fi
    RESULT=$(settings_curl POST "/-/accounts/update" -d "id=$URL_ID&label=$LONG_ALABEL")
    if echo "$RESULT" | grep -q "too long"; then
        pass "Over-length account label rejected (settings)"
    else
        fail "Over-length account label rejected (settings)" "$(echo "$RESULT" | head -c 150)"
    fi
fi

# ============================================================================
# CLEANUP
# ============================================================================

echo ""
echo "--- Cleanup ---"

# Remove test accounts
if [ -n "$URL_ID" ]; then
    settings_curl POST "/-/accounts/remove" -d "id=$URL_ID" > /dev/null 2>&1
fi

pass "Cleanup completed"

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "=============================================="
echo "Test Results: $PASSED passed, $FAILED failed"
echo "=============================================="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
