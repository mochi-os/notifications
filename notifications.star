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

