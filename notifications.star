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
	mochi.db.execute("""create table if not exists subscriptions (
		id text not null primary key,
		endpoint text not null unique,
		auth text not null,
		p256dh text not null,
		created integer not null
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

def database_downgrade(from_version):
	if from_version == 4:
		mochi.db.execute("drop table if exists subscriptions")

# Expiry: 30 days unread, 7 days read
def function_expire():
	now = mochi.time.now()
	mochi.db.execute("delete from notifications where read = 0 and created < ?", now - 30 * 86400)
	mochi.db.execute("delete from notifications where read != 0 and created < ?", now - 7 * 86400)

def function_clear_all():
	mochi.db.execute("delete from notifications")

def function_clear_app(app):
	mochi.db.execute("delete from notifications where app = ?", app)

def function_clear_object(app, object):
	mochi.db.execute("delete from notifications where app = ? and object = ?", app, object)

def function_create(app, category, object, content, link):
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

	# Send push notification
	send_push(content, link, app + "-" + category + "-" + object)

def function_list():
	return mochi.db.rows("select * from notifications order by created desc")

def function_read(id):
	now = mochi.time.now()
	mochi.db.execute("update notifications set read = ? where id = ?", now, id)
	mochi.websocket.write("notifications", {"type": "read", "id": id})

def function_read_all():
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
	function_expire()
	rows = function_list()
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
	function_read(id)
	return {"data": {}}

def action_read_all(a):
	function_read_all()
	return {"data": {}}

def action_clear_all(a):
	function_clear_all()
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
	# Authentication is handled by the server via cookie, Bearer token, or query parameter token.
	# The server validates the token's app scope automatically.
	if not a.user:
		a.error(401, "Authentication required")
		return

	function_expire()
	rows = mochi.db.rows("""
		select id, app, category, content, link, count, created
		from notifications order by created desc limit 100
	""")

	a.header("Content-Type", "application/rss+xml; charset=utf-8")

	a.print('<?xml version="1.0" encoding="UTF-8"?>\n')
	a.print('<rss version="2.0">\n')
	a.print('<channel>\n')
	a.print('<title>Notifications</title>\n')
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

# Push notification endpoints

def action_push_key(a):
	"""Return VAPID public key for client subscription"""
	key = mochi.webpush.key()
	if not key:
		a.error(503, "Push notifications not available")
		return
	return {"data": {"key": key}}

def action_push_subscribe(a):
	"""Subscribe to push notifications"""
	endpoint = a.input("endpoint", "").strip()
	auth = a.input("auth", "").strip()
	p256dh = a.input("p256dh", "").strip()

	if not endpoint or not auth or not p256dh:
		a.error(400, "Missing subscription data")
		return

	if len(endpoint) > 2048 or len(auth) > 256 or len(p256dh) > 256:
		a.error(400, "Invalid subscription data")
		return

	now = mochi.time.now()
	id = mochi.uid()

	# Upsert subscription (endpoint is unique per browser)
	mochi.db.execute("""
		insert into subscriptions (id, endpoint, auth, p256dh, created)
		values (?, ?, ?, ?, ?)
		on conflict(endpoint) do update set auth=?, p256dh=?, created=?
	""", id, endpoint, auth, p256dh, now, auth, p256dh, now)

	return {"data": {"ok": True}}

def action_push_unsubscribe(a):
	"""Unsubscribe from push notifications"""
	endpoint = a.input("endpoint", "").strip()

	if not endpoint:
		a.error(400, "Missing endpoint")
		return

	mochi.db.execute("delete from subscriptions where endpoint = ?", endpoint)
	return {"data": {"ok": True}}

def send_push(body, link, tag):
	"""Send push notification to all subscriptions"""
	payload = json.encode({
		"title": "Mochi",
		"body": body,
		"link": link,
		"tag": tag
	})

	rows = mochi.db.rows("select endpoint, auth, p256dh from subscriptions")

	for row in rows:
		success = mochi.webpush.send(
			endpoint=row["endpoint"],
			auth=row["auth"],
			p256dh=row["p256dh"],
			payload=payload
		)

		# Remove expired/invalid subscriptions
		if not success:
			mochi.db.execute("delete from subscriptions where endpoint = ?", row["endpoint"])

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
	for key in ["label", "address", "token", "api_key", "url", "endpoint", "auth", "p256dh"]:
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
