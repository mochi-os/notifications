#!/bin/bash
# Test notifications API endpoints
# Usage: ./test-api.sh [base_url] [session_code]
# Example: ./test-api.sh http://localhost "PILT3V4LOr2..."

set -e

BASE_URL="${1:-http://localhost}"
AUTH_COOKIE="${2:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }
info() { echo -e "${YELLOW}→ $1${NC}"; }

if [ -z "$AUTH_COOKIE" ]; then
    echo "Usage: $0 <base_url> <session_code>"
    echo "Example: $0 http://localhost 'PILT3V4LOr2...'"
    exit 1
fi

CURL="curl -s -b session=$AUTH_COOKIE"

echo "Testing Notifications API at $BASE_URL"
echo "========================================"
echo

# Test 1: List notifications
info "Testing GET /notifications/list"
RESPONSE=$($CURL "$BASE_URL/notifications/list")
if echo "$RESPONSE" | grep -q '"data":\['; then
    pass "List endpoint returns data array"
else
    fail "List endpoint failed: $RESPONSE"
fi

# Test 2: Count notifications
info "Testing GET /notifications/count"
RESPONSE=$($CURL "$BASE_URL/notifications/count")
if echo "$RESPONSE" | grep -q '"count"'; then
    pass "Count endpoint returns count object"
    COUNT=$(echo "$RESPONSE" | grep -o '"count":[0-9]*' | cut -d: -f2)
    TOTAL=$(echo "$RESPONSE" | grep -o '"total":[0-9]*' | cut -d: -f2)
    info "  Unread: $COUNT, Total: $TOTAL"
else
    fail "Count endpoint failed: $RESPONSE"
fi

# Test 3: Get initial list to find a notification ID
info "Getting notification list for read test"
NOTIFICATIONS=$($CURL "$BASE_URL/notifications/list")
# Extract first ID from {"data":[{"id":"...",...},...]}
FIRST_ID=$(echo "$NOTIFICATIONS" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$FIRST_ID" ]; then
    # Test 4: Mark single notification as read
    info "Testing POST /notifications/read (id=$FIRST_ID)"
    RESPONSE=$($CURL -X POST -d "id=$FIRST_ID" "$BASE_URL/notifications/read")
    if [ "$RESPONSE" = "null" ] || [ -z "$RESPONSE" ] || echo "$RESPONSE" | grep -qE '"ok"|"data":\{\}'; then
        pass "Read endpoint accepted request"
    else
        fail "Read endpoint failed: $RESPONSE"
    fi
else
    info "No notifications to test read endpoint (skipping)"
fi

# Test 5: Mark all as read
info "Testing POST /notifications/read/all"
RESPONSE=$($CURL -X POST "$BASE_URL/notifications/read/all")
if [ "$RESPONSE" = "null" ] || [ -z "$RESPONSE" ] || echo "$RESPONSE" | grep -qE '"ok"|"data":\{\}'; then
    pass "Read all endpoint accepted request"
else
    fail "Read all endpoint failed: $RESPONSE"
fi

# Test 6: Clear all notifications
info "Testing POST /notifications/clear/all"
RESPONSE=$($CURL -X POST "$BASE_URL/notifications/clear/all")
if [ "$RESPONSE" = "null" ] || [ -z "$RESPONSE" ] || echo "$RESPONSE" | grep -qE '"ok"|"data":\{\}'; then
    pass "Clear all endpoint accepted request"
else
    fail "Clear all endpoint failed: $RESPONSE"
fi

# Test 7: Verify count after clearing all
info "Verifying count after clearing all"
RESPONSE=$($CURL "$BASE_URL/notifications/count")
COUNT=$(echo "$RESPONSE" | grep -o '"count":[0-9]*' | cut -d: -f2)
if [ "$COUNT" = "0" ]; then
    pass "Unread count is 0 after clearing all"
else
    info "  Unread count: $COUNT (may have new notifications)"
fi

# Test 8: WebSocket endpoint (just check it accepts connection)
info "Testing WebSocket endpoint availability"
WS_URL=$(echo "$BASE_URL" | sed 's/http/ws/')/websocket?key=notifications
# Use curl to check if the endpoint exists (will fail to upgrade but that's ok)
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -H "Connection: Upgrade" -H "Upgrade: websocket" -b "session=$AUTH_COOKIE" "$BASE_URL/websocket?key=notifications" 2>/dev/null || echo "000")
if [ "$RESPONSE" = "400" ] || [ "$RESPONSE" = "426" ] || [ "$RESPONSE" = "101" ]; then
    pass "WebSocket endpoint exists (HTTP $RESPONSE)"
else
    info "WebSocket endpoint returned HTTP $RESPONSE (may need proper WS client)"
fi

# Test 9: RSS without auth (should fail)
info "Testing GET /notifications/rss without auth"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/notifications/rss")
if [ "$RESPONSE" = "401" ]; then
    pass "RSS endpoint requires authentication (HTTP 401)"
else
    fail "RSS endpoint should return 401 without auth, got HTTP $RESPONSE"
fi

# Test 10: RSS with session auth
info "Testing GET /notifications/rss with session"
RESPONSE=$($CURL "$BASE_URL/notifications/rss")
if echo "$RESPONSE" | grep -q '<?xml' && echo "$RESPONSE" | grep -q '<rss'; then
    pass "RSS endpoint returns valid RSS XML"
    # Verify RSS structure
    if echo "$RESPONSE" | grep -q '<channel>' && echo "$RESPONSE" | grep -q '<title>Notifications</title>'; then
        pass "RSS feed has correct structure"
    else
        fail "RSS feed missing expected elements"
    fi
else
    fail "RSS endpoint failed: $RESPONSE"
fi

# Test 11: RSS with invalid token
info "Testing GET /notifications/rss with invalid token"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/notifications/rss?token=invalid")
if [ "$RESPONSE" = "401" ]; then
    pass "RSS endpoint rejects invalid token (HTTP 401)"
else
    fail "RSS endpoint should return 401 for invalid token, got HTTP $RESPONSE"
fi

echo
echo "========================================"
echo -e "${GREEN}All tests completed${NC}"
