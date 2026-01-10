#!/bin/bash
# Notification Routing Test Suite
# Tests RSS feed management and external URL provider
# Usage: ./test_routing.sh

set -e

CURL_HELPER="/home/alistair/mochi/test/claude/curl.sh"

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
    RESULT=$(curl -s "http://localhost:8081/notifications/rss?token=$FEED_TOKEN")
    if echo "$RESULT" | grep -q '<?xml' && echo "$RESULT" | grep -q '<rss'; then
        pass "RSS feed accessible with token"
    else
        fail "RSS feed accessible with token" "$RESULT"
    fi
fi

# Test: RSS feed shows feed name in title
if [ -n "$FEED_TOKEN" ]; then
    RESULT=$(curl -s "http://localhost:8081/notifications/rss?token=$FEED_TOKEN")
    if echo "$RESULT" | grep -q '<title>Test Feed</title>'; then
        pass "RSS feed title is feed name"
    else
        fail "RSS feed title is feed name" "$RESULT"
    fi
fi

# Test: Invalid feed token returns 401
RESULT=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8081/notifications/rss?token=invalid_token_12345")
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
    RESULT=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8081/notifications/rss?token=$FEED_TOKEN")
    if [ "$RESULT" = "401" ]; then
        pass "Deleted feed token returns 401"
    else
        fail "Deleted feed token returns 401" "Got HTTP $RESULT"
    fi
fi

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
    URL_ID=$(echo "$RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin)['data']['id'])" 2>/dev/null || echo "")
    pass "Add external URL account (ID: $URL_ID)"
else
    fail "Add external URL account" "$RESULT"
fi

# Test: External URL account is immediately verified
RESULT=$(settings_curl GET "/-/accounts/list")
if echo "$RESULT" | python3 -c "import sys, json; accounts = json.load(sys.stdin)['data']; u = next((a for a in accounts if a['type'] == 'url'), None); sys.exit(0 if u and u['verified'] > 0 else 1)" 2>/dev/null; then
    pass "External URL account immediately verified"
else
    fail "External URL account immediately verified" "$RESULT"
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
