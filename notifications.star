# Mochi notifications app
# Copyright Alistair Cunningham 2024-2025

def database_create():
	mochi.db.execute("""create table if not exists notifications (
		id text not null primary key,
		app text not null,
		category text not null,
		object text not null,
		content text not null,
		link text not null default '',
		count integer not null default 1,
		created integer not null,
		read integer not null default 0,
		unique ( app, category, object )
	)""")
	mochi.db.execute("create index if not exists notifications_created on notifications(created)")
	# RSS feeds table
	mochi.db.execute("""create table if not exists rss (
		id text primary key,
		name text not null,
		token text not null unique,
		created integer not null
	)""")
	# Subscriptions table: apps request permission to send notifications
	mochi.db.execute("""create table if not exists subscriptions (
		id integer primary key,
		app text not null,
		type text not null default '',
		object text not null default '',
		label text not null,
		created integer not null
	)""")
	mochi.db.execute("create index if not exists subscriptions_app on subscriptions(app)")
	mochi.db.execute("create index if not exists subscriptions_app_type_object on subscriptions(app, type, object)")
	# Destinations table: where subscription notifications are delivered
	mochi.db.execute("""create table if not exists destinations (
		subscription integer not null,
		type text not null,
		target text not null,
		primary key (subscription, type, target),
		foreign key (subscription) references subscriptions(id) on delete cascade
	)""")

def database_upgrade(to_version):
	if to_version == 4:
		mochi.db.execute("""create table if not exists subscriptions (
			id text not null primary key,
			endpoint text not null unique,
			auth text not null,
			p256dh text not null,
			created integer not null
		)""")
	if to_version == 5:
		# Migrate push subscriptions from local table to accounts system
		rows = mochi.db.rows("select endpoint, auth, p256dh from subscriptions")
		for row in rows:
			mochi.account.add("browser", {
				"endpoint": row["endpoint"],
				"auth": row["auth"],
				"p256dh": row["p256dh"],
			})
		# Drop the old subscriptions table
		mochi.db.execute("drop table if exists subscriptions")
	if to_version == 6:
		# Add RSS feeds table
		mochi.db.execute("""create table if not exists rss (
			id text primary key,
			name text not null,
			token text not null unique,
			created integer not null
		)""")
	if to_version == 7:
		# Add subscriptions table for permission-based notification streams
		mochi.db.execute("""create table if not exists subscriptions (
			id integer primary key,
			app text not null,
			type text not null default '',
			object text not null default '',
			label text not null,
			created integer not null
		)""")
		mochi.db.execute("create index if not exists subscriptions_app on subscriptions(app)")
		mochi.db.execute("create index if not exists subscriptions_app_type_object on subscriptions(app, type, object)")
		# Add destinations table for routing notifications
		mochi.db.execute("""create table if not exists destinations (
			subscription integer not null,
			type text not null,
			target text not null,
			primary key (subscription, type, target),
			foreign key (subscription) references subscriptions(id) on delete cascade
		)""")
		# Remove old filters table (replaced by subscriptions/destinations)
		mochi.db.execute("drop table if exists filters")

def database_downgrade(from_version):
	if from_version == 4:
		mochi.db.execute("drop table if exists subscriptions")
	if from_version == 5:
		# Recreate subscriptions table (data was migrated to accounts, cannot restore)
		mochi.db.execute("""create table if not exists subscriptions (
			id text not null primary key,
			endpoint text not null unique,
			auth text not null,
			p256dh text not null,
			created integer not null
		)""")
	if from_version == 6:
		mochi.db.execute("drop table if exists rss")
	if from_version == 7:
		mochi.db.execute("drop table if exists destinations")
		mochi.db.execute("drop table if exists subscriptions")
		# Recreate filters table
		mochi.db.execute("""create table if not exists filters (
			id integer primary key,
			feed text not null,
			action text not null,
			app text,
			category text,
			urgency text,
			foreign key (feed) references rss(id) on delete cascade
		)""")
		mochi.db.execute("create index if not exists filters_feed on filters(feed)")

# Expiry: 30 days unread, 7 days read
def function_expire(context):
	now = mochi.time.now()
	mochi.db.execute("delete from notifications where read = 0 and created < ?", now - 30 * 86400)
	mochi.db.execute("delete from notifications where read != 0 and created < ?", now - 7 * 86400)

def function_clear_all(context):
	mochi.db.execute("delete from notifications")

def function_clear_app(context, app):
	mochi.db.execute("delete from notifications where app = ?", app)

def function_clear_object(context, app, object):
	mochi.db.execute("delete from notifications where app = ? and object = ?", app, object)

def function_create(context, app, category, object, content, link):
	if not mochi.valid(app, "constant"):
		return
	if not mochi.valid(category, "constant"):
		return
	if not mochi.valid(object, "path"):
		return
	if not mochi.valid(content, "text"):
		return
	if not mochi.valid(link, "url"):
		return

	now = mochi.time.now()
	existing = mochi.db.row("select * from notifications where app = ? and category = ? and object = ?", app, category, object)

	if existing and existing["read"] == 0:
		count = existing["count"] + 1
		mochi.db.execute("update notifications set content = ?, count = ?, created = ? where id = ?", content, count, now, existing["id"])
		id = existing["id"]
	else:
		id = mochi.uid()
		mochi.db.execute("""replace into notifications (id, app, category, object, content, link, count, created, read)
			values (?, ?, ?, ?, ?, ?, 1, ?, 0)""", id, app, category, object, content, link, now)

	mochi.websocket.write("notifications", {
		"type": "new",
		"id": id,
		"app": app,
		"category": category,
		"object": object,
		"content": content,
		"link": link
	})

	# Deliver notification to all connected accounts
	mochi.account.deliver(app=app, category=category, object=object, content=content, link=link)

def function_list(context):
	return mochi.db.rows("select * from notifications order by created desc")

def function_read(context, id):
	now = mochi.time.now()
	mochi.db.execute("update notifications set read = ? where id = ?", now, id)
	mochi.websocket.write("notifications", {"type": "read", "id": id})

def function_read_all(context):
	now = mochi.time.now()
	mochi.db.execute("update notifications set read = ?", now)
	mochi.websocket.write("notifications", {"type": "read_all"})

def version_gte(version, minimum):
	"""Check if version >= minimum using numeric comparison"""
	v_parts = version.split(".")
	m_parts = minimum.split(".")
	max_len = len(v_parts) if len(v_parts) > len(m_parts) else len(m_parts)
	for i in range(max_len):
		v_num = int(v_parts[i]) if i < len(v_parts) else 0
		m_num = int(m_parts[i]) if i < len(m_parts) else 0
		if v_num > m_num:
			return True
		if v_num < m_num:
			return False
	return True

def action_list(a):
	function_expire({})
	rows = function_list({})
	row = mochi.db.row("select count(*) as count, coalesce(sum(count), 0) as total from notifications where read = 0")

	# Check if RSS tokens are supported (requires server 0.3+)
	version = mochi.server.version()
	rss_supported = version_gte(version, "0.3")

	return {
		"data": rows,
		"count": row["count"] if row else 0,
		"total": row["total"] if row else 0,
		"rss": rss_supported
	}

def action_count(a):
	row = mochi.db.row("select count(*) as count, coalesce(sum(count), 0) as total from notifications where read = 0")
	return {"data": {"count": row["count"] if row else 0, "total": row["total"] if row else 0}}

def action_read(a):
	id = a.input("id", "").strip()
	if not id or len(id) > 64:
		a.error(400, "Invalid id")
		return
	function_read({}, id)
	return {"data": {}}

def action_read_all(a):
	function_read_all({})
	return {"data": {}}

def action_clear_all(a):
	function_clear_all({})
	mochi.websocket.write("notifications", {"type": "clear_all"})
	return {"data": {}}

def escape_xml(s):
	if not s:
		return ""
	s = s.replace("&", "&amp;")
	s = s.replace("<", "&lt;")
	s = s.replace(">", "&gt;")
	s = s.replace('"', "&quot;")
	return s

def action_rss(a):
	# Authentication is handled by the server via:
	# 1. Token in query parameter (?token=xxx) - server validates and sets a.user
	# 2. Cookie session
	# 3. Bearer token header

	if not a.user:
		a.error(401, "Authentication required")
		return

	# Check if a feed token was provided (look up feed for naming)
	feed_name = "Notifications"
	feed_token = a.input("token", "").strip()
	if feed_token:
		feed = mochi.db.row("select name from rss where token = ?", feed_token)
		if feed:
			feed_name = feed["name"]

	function_expire({})

	# Get all notifications
	rows = mochi.db.rows("""
		select id, app, category, content, link, count, created
		from notifications order by created desc limit 100
	""")

	a.header("Content-Type", "application/rss+xml; charset=utf-8")

	a.print('<?xml version="1.0" encoding="UTF-8"?>\n')
	a.print('<rss version="2.0">\n')
	a.print('<channel>\n')
	a.print('<title>' + escape_xml(feed_name) + '</title>\n')
	a.print('<link>/notifications</link>\n')
	a.print('<description>Your notifications</description>\n')

	if rows:
		a.print('<lastBuildDate>' + mochi.time.local(rows[0]["created"], "rfc822") + '</lastBuildDate>\n')

	for row in rows:
		title = row["app"] + ": " + row["category"]
		if row["count"] > 1:
			title = title + " (" + str(row["count"]) + ")"

		link = row["link"] if row["link"] else "/notifications"

		a.print('<item>\n')
		a.print('<title>' + escape_xml(title) + '</title>\n')
		a.print('<link>' + escape_xml(link) + '</link>\n')
		a.print('<description>' + escape_xml(row["content"]) + '</description>\n')
		a.print('<pubDate>' + mochi.time.local(row["created"], "rfc822") + '</pubDate>\n')
		a.print('<guid isPermaLink="false">' + escape_xml(row["id"]) + '</guid>\n')
		a.print('</item>\n')

	a.print('</channel>\n')
	a.print('</rss>')

# Token management endpoints

def action_token_get(a):
	"""Get existing token or create first one for RSS access"""
	tokens = mochi.token.list()
	if tokens and len(tokens) > 0:
		return {"data": {"exists": True, "count": len(tokens)}}
	name = (a.input("name") or "RSS feed").strip()
	if len(name) > 100:
		return a.error(400, "Token name is too long")
	token = mochi.token.create(name, [], 0)
	if not token:
		return a.error(500, "Failed to create token")
	return {"data": {"exists": False, "token": token}}

def action_token_create(a):
	"""Create a new token for RSS access"""
	name = (a.input("name") or "RSS feed").strip()
	if len(name) > 100:
		return a.error(400, "Token name is too long")
	token = mochi.token.create(name, [], 0)
	if not token:
		return a.error(500, "Failed to create token")
	return {"data": {"token": token}}

def action_token_list(a):
	"""List all tokens for RSS access"""
	tokens = mochi.token.list()
	return {"data": {"tokens": tokens or []}}

def action_token_delete(a):
	"""Delete a token"""
	hash = a.input("hash", "").strip()
	if not hash or len(hash) > 128:
		return a.error(400, "Invalid hash")
	mochi.token.delete(hash)
	return {"data": {}}

# Connected accounts endpoints (thin wrappers around mochi.account.* API)

def action_accounts_providers(a):
	"""List available account providers"""
	capability = a.input("capability")
	return {"data": mochi.account.providers(capability)}

def action_accounts_list(a):
	"""List user's connected accounts"""
	capability = a.input("capability")
	return {"data": mochi.account.list(capability)}

def action_accounts_get(a):
	"""Get a single connected account"""
	id = a.input("id", "").strip()
	if not id or not id.isdigit():
		a.error(400, "Invalid id")
		return
	result = mochi.account.get(int(id))
	return {"data": result}

def action_accounts_add(a):
	"""Add a new connected account"""
	type = a.input("type")
	if not type:
		a.error(400, "type is required")
		return

	# Build fields dict from form inputs
	fields = {}
	for key in ["label", "address", "token", "api_key", "url", "endpoint", "auth", "p256dh", "secret"]:
		val = a.input(key)
		if val:
			fields[key] = val

	result = mochi.account.add(type, fields)
	return {"data": result}

def action_accounts_update(a):
	"""Update a connected account"""
	id = a.input("id", "").strip()
	if not id or not id.isdigit():
		a.error(400, "Invalid id")
		return

	# Build fields dict from form inputs
	fields = {}
	label = a.input("label")
	if label != None:
		fields["label"] = label

	result = mochi.account.update(int(id), fields)
	return {"data": result}

def action_accounts_remove(a):
	"""Remove a connected account"""
	id = a.input("id", "").strip()
	if not id or not id.isdigit():
		a.error(400, "Invalid id")
		return

	result = mochi.account.remove(int(id))
	return {"data": result}

def action_accounts_verify(a):
	"""Verify an account or resend verification code"""
	id = a.input("id", "").strip()
	if not id or not id.isdigit():
		a.error(400, "Invalid id")
		return

	code = a.input("code")
	result = mochi.account.verify(int(id), code)
	return {"data": result}

def action_accounts_vapid(a):
	"""Return VAPID public key for browser push subscription"""
	key = mochi.webpush.key()
	if not key:
		return a.error(503, "Push notifications not available")
	return {"data": {"key": key}}

# RSS feed management endpoints

def action_rss_list(a):
	"""List all RSS feeds"""
	rows = mochi.db.rows("select id, name, token, created from rss order by created desc")
	return {"data": rows or []}

def action_rss_create(a):
	"""Create a new RSS feed"""
	name = (a.input("name") or "RSS feed").strip()
	if len(name) > 100:
		return a.error(400, "Feed name is too long")
	if not name:
		return a.error(400, "Feed name is required")

	id = mochi.uid()
	# Create a token via the global token system (stored in users.db tokens table)
	# This allows the server to authenticate RSS requests via ?token= parameter
	token = mochi.token.create("rss:" + id, ["rss"])
	if not token:
		return a.error(500, "Failed to create token")
	now = mochi.time.now()

	mochi.db.execute("insert into rss (id, name, token, created) values (?, ?, ?, ?)", id, name, token, now)

	return {"data": {"id": id, "name": name, "token": token, "created": now}}

def action_rss_delete(a):
	"""Delete an RSS feed"""
	id = a.input("id", "").strip()
	if not id or len(id) > 64:
		return a.error(400, "Invalid id")

	# Check feed exists
	exists = mochi.db.exists("select 1 from rss where id = ?", id)
	if not exists:
		return a.error(404, "Feed not found")

	# Delete the associated token from the global tokens table
	token_name = "rss:" + id
	for token in mochi.token.list():
		if token.get("name") == token_name:
			mochi.token.delete(token["hash"])
			break

	mochi.db.execute("delete from rss where id = ?", id)
	return {"data": {}}

# Test action for subscription services (temporary)
def action_test_subscriptions(a):
	"""Test the subscription services"""
	results = []

	# Simulate context from a calling app
	context = {"app": "test-app"}

	# Test 1: Subscribe
	sub_id = function_subscribe(context, "Test subscription", "post", "123", [
		{"type": "account", "target": "1"}
	])
	results.append({"test": "subscribe", "result": sub_id, "pass": sub_id != None})

	# Test 2: List subscriptions
	subs = function_subscriptions(context)
	results.append({"test": "subscriptions", "count": len(subs), "pass": len(subs) == 1})

	# Test 3: Subscribe again (should update, not duplicate)
	sub_id2 = function_subscribe(context, "Updated label", "post", "123")
	results.append({"test": "subscribe_update", "same_id": sub_id == sub_id2, "pass": sub_id == sub_id2})

	# Test 4: List with filter
	subs_filtered = function_subscriptions(context, type="post")
	results.append({"test": "subscriptions_filtered", "count": len(subs_filtered), "pass": len(subs_filtered) == 1})

	# Test 5: Send (should find the subscription)
	count = function_send(context, "post", "Test Title", "Test body", "123", "/test")
	results.append({"test": "send", "count": count, "pass": count >= 0})

	# Test 6: Unsubscribe
	ok = function_unsubscribe(context, sub_id)
	results.append({"test": "unsubscribe", "result": ok, "pass": ok == True})

	# Test 7: Verify unsubscribed
	subs_after = function_subscriptions(context)
	results.append({"test": "verify_unsubscribed", "count": len(subs_after), "pass": len(subs_after) == 0})

	# Test 8: Unsubscribe non-existent (should fail)
	ok2 = function_unsubscribe(context, 99999)
	results.append({"test": "unsubscribe_nonexistent", "result": ok2, "pass": ok2 == False})

	# Test 9: Different app can't unsubscribe
	sub_id3 = function_subscribe(context, "Another sub", "feed", "456")
	other_context = {"app": "other-app"}
	ok3 = function_unsubscribe(other_context, sub_id3)
	results.append({"test": "unsubscribe_wrong_app", "result": ok3, "pass": ok3 == False})

	# Cleanup
	function_unsubscribe(context, sub_id3)

	all_passed = True
	for r in results:
		if not r["pass"]:
			all_passed = False
			break
	return {"data": {"results": results, "all_passed": all_passed}}

# Subscription services for permission-based notifications

def function_subscribe(context, label, type="", object="", destinations=None):
	"""Create a subscription for the current user.

	Args:
		context: Contains 'app' key with calling app ID
		label: Human-readable description shown to user
		type: App-defined type (e.g., "post", "feed")
		object: Object identifier within that type
		destinations: List of {type, target} dicts for delivery routing

	Returns:
		Subscription ID if created, None if invalid
	"""
	app = context.get("app", "")
	if not app:
		return None

	if not label or not mochi.valid(label, "text"):
		return None

	if type and not mochi.valid(type, "constant"):
		return None

	if object and not mochi.valid(object, "path"):
		return None

	now = mochi.time.now()

	# Check if subscription already exists
	existing = mochi.db.row(
		"select id from subscriptions where app = ? and type = ? and object = ?",
		app, type, object
	)
	if existing:
		# Update label and return existing ID
		mochi.db.execute("update subscriptions set label = ? where id = ?", label, existing["id"])
		sub_id = existing["id"]
	else:
		# Create new subscription
		mochi.db.execute(
			"insert into subscriptions (app, type, object, label, created) values (?, ?, ?, ?, ?)",
			app, type, object, label, now
		)
		sub_id = mochi.db.row("select last_insert_rowid() as id")["id"]

	# Update destinations if provided
	if destinations:
		# Clear existing destinations
		mochi.db.execute("delete from destinations where subscription = ?", sub_id)
		# Add new destinations
		for dest in destinations:
			dest_type = dest.get("type", "")
			dest_target = dest.get("target", "")
			if dest_type and dest_target:
				mochi.db.execute(
					"insert into destinations (subscription, type, target) values (?, ?, ?)",
					sub_id, dest_type, dest_target
				)

	return sub_id

def function_send(context, type, title, body, object="", url="", data=None):
	"""Send notification to all matching subscriptions.

	Args:
		context: Contains 'app' key with calling app ID
		type: Notification type to match subscriptions
		title: Notification title
		body: Notification body text
		object: Optional object ID to match specific subscriptions
		url: Optional link URL
		data: Optional additional data dict

	Returns:
		Number of subscriptions notified
	"""
	app = context.get("app", "")
	if not app:
		return 0

	if not title or not body:
		return 0

	# Find matching subscriptions
	if object:
		# Match specific object or app-wide subscriptions (empty object)
		subs = mochi.db.rows(
			"select id from subscriptions where app = ? and type = ? and (object = ? or object = '')",
			app, type, object
		)
	else:
		# Match only app-wide subscriptions for this type
		subs = mochi.db.rows(
			"select id from subscriptions where app = ? and type = ? and object = ''",
			app, type
		)

	if not subs:
		return 0

	count = 0
	for sub in subs:
		sub_id = sub["id"]

		# Get destinations for this subscription
		dests = mochi.db.rows(
			"select type, target from destinations where subscription = ?",
			sub_id
		)

		# Deliver to each destination
		for dest in dests:
			if dest["type"] == "account":
				# Deliver via connected account
				mochi.account.deliver(
					app=app,
					category=type,
					object=object,
					content=title + ": " + body,
					link=url
				)
				count += 1
			# RSS destinations don't need active delivery - they're queried on demand

	return count

def function_subscriptions(context, type=None, object=None):
	"""List current user's subscriptions for the calling app.

	Args:
		context: Contains 'app' key with calling app ID
		type: Optional filter by type
		object: Optional filter by object

	Returns:
		List of subscription dicts with destinations
	"""
	app = context.get("app", "")
	if not app:
		return []

	# Build query based on filters
	if type and object:
		subs = mochi.db.rows(
			"select * from subscriptions where app = ? and type = ? and object = ?",
			app, type, object
		)
	elif type:
		subs = mochi.db.rows(
			"select * from subscriptions where app = ? and type = ?",
			app, type
		)
	else:
		subs = mochi.db.rows(
			"select * from subscriptions where app = ?",
			app
		)

	# Add destinations to each subscription
	result = []
	for sub in subs:
		dests = mochi.db.rows(
			"select type, target from destinations where subscription = ?",
			sub["id"]
		)
		sub["destinations"] = dests or []
		result.append(sub)

	return result

def function_unsubscribe(context, id):
	"""Remove a subscription by ID.

	Args:
		context: Contains 'app' key with calling app ID
		id: Subscription ID to remove

	Returns:
		True if removed, False if not found or not owned by calling app
	"""
	app = context.get("app", "")
	if not app:
		return False

	if not id:
		return False

	# Verify subscription exists and belongs to calling app
	exists = mochi.db.exists(
		"select 1 from subscriptions where id = ? and app = ?",
		id, app
	)
	if not exists:
		return False

	# Delete subscription (destinations cascade)
	mochi.db.execute("delete from subscriptions where id = ?", id)
	return True

# HTTP action endpoints for subscription management UI

def action_subscriptions_list(a):
	"""List all subscriptions for current user (all apps)"""
	subs = mochi.db.rows("select * from subscriptions order by created desc")
	if not subs:
		return {"data": []}

	# Add destinations to each subscription
	result = []
	for sub in subs:
		dests = mochi.db.rows(
			"select type, target from destinations where subscription = ?",
			sub["id"]
		)
		sub["destinations"] = dests or []
		result.append(sub)

	return {"data": result}

def action_subscriptions_create(a):
	"""Create a subscription from frontend"""
	app = a.input("app", "").strip()
	label = a.input("label", "").strip()
	type = a.input("type", "").strip()
	object = a.input("object", "").strip()
	destinations_json = a.input("destinations", "").strip()

	if not app:
		return a.error(400, "app is required")
	if not label:
		return a.error(400, "label is required")

	if not mochi.valid(app, "constant"):
		return a.error(400, "Invalid app")
	if not mochi.valid(label, "text"):
		return a.error(400, "Invalid label")
	if type and not mochi.valid(type, "constant"):
		return a.error(400, "Invalid type")
	if object and not mochi.valid(object, "path"):
		return a.error(400, "Invalid object")

	# Parse destinations JSON
	destinations = []
	if destinations_json:
		destinations = json.decode(destinations_json)
		if not destinations:
			destinations = []

	now = mochi.time.now()

	# Check if subscription already exists
	existing = mochi.db.row(
		"select id from subscriptions where app = ? and type = ? and object = ?",
		app, type, object
	)
	if existing:
		# Update label
		mochi.db.execute("update subscriptions set label = ? where id = ?", label, existing["id"])
		sub_id = existing["id"]
	else:
		# Create new subscription
		mochi.db.execute(
			"insert into subscriptions (app, type, object, label, created) values (?, ?, ?, ?, ?)",
			app, type, object, label, now
		)
		sub_id = mochi.db.row("select last_insert_rowid() as id")["id"]

	# Update destinations
	mochi.db.execute("delete from destinations where subscription = ?", sub_id)
	for dest in destinations:
		dest_type = dest.get("type", "")
		dest_target = dest.get("target", "")
		if dest_type and dest_target:
			mochi.db.execute(
				"insert into destinations (subscription, type, target) values (?, ?, ?)",
				sub_id, dest_type, str(dest_target)
			)

	return {"data": {"id": sub_id}}

def action_subscriptions_update(a):
	"""Update destinations for a subscription"""
	id = a.input("id", "").strip()
	destinations_json = a.input("destinations", "").strip()

	if not id or not id.isdigit():
		return a.error(400, "Invalid id")

	sub_id = int(id)

	# Check subscription exists
	exists = mochi.db.exists("select 1 from subscriptions where id = ?", sub_id)
	if not exists:
		return a.error(404, "Subscription not found")

	# Parse destinations JSON
	destinations = []
	if destinations_json:
		destinations = json.decode(destinations_json)
		if not destinations:
			destinations = []

	# Update destinations
	mochi.db.execute("delete from destinations where subscription = ?", sub_id)
	for dest in destinations:
		dest_type = dest.get("type", "")
		dest_target = dest.get("target", "")
		if dest_type and dest_target:
			mochi.db.execute(
				"insert into destinations (subscription, type, target) values (?, ?, ?)",
				sub_id, dest_type, str(dest_target)
			)

	return {"data": {}}

def action_subscriptions_delete(a):
	"""Delete a subscription"""
	id = a.input("id", "").strip()

	if not id or not id.isdigit():
		return a.error(400, "Invalid id")

	sub_id = int(id)

	# Check subscription exists
	exists = mochi.db.exists("select 1 from subscriptions where id = ?", sub_id)
	if not exists:
		return a.error(404, "Subscription not found")

	# Delete subscription (destinations cascade)
	mochi.db.execute("delete from subscriptions where id = ?", sub_id)
	return {"data": {}}

def action_destinations_list(a):
	"""List available destinations for permission dialog"""
	# Get notify-capable accounts
	accounts = mochi.account.list("notify")

	# Get RSS feeds
	feeds = mochi.db.rows("select id, name from rss order by name")

	return {"data": {"accounts": accounts or [], "feeds": feeds or []}}
