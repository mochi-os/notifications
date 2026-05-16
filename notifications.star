# Mochi notifications app
# Copyright Alistair Cunningham 2024-2026

def database_create():
	mochi.db.execute("""create table if not exists notifications (
		id text not null primary key,
		app text not null,
		topic text not null,
		object text not null,
		content text not null,
		link text not null default '',
		sender text not null default '',
		count integer not null default 1,
		created integer not null,
		read integer not null default 0,
		unique ( app, topic, object )
	)""")
	mochi.db.execute("create index if not exists notifications_created on notifications(created)")

	mochi.db.execute("""create table if not exists rss (
		id text primary key,
		name text not null,
		token text not null unique,
		created integer not null,
		enabled integer not null default 1
	)""")

	mochi.db.execute("""create table if not exists categories (
		id integer primary key,
		label text not null,
		"default" integer not null default 0,
		created integer not null
	)""")

	mochi.db.execute("""create table if not exists topics (
		id integer primary key,
		app text not null,
		topic text not null default '',
		object text not null default '',
		label text not null default '',
		category integer,
		created integer not null
	)""")
	mochi.db.execute("create unique index if not exists topics_app_topic_object on topics(app, topic, object)")

	mochi.db.execute("""create table if not exists destinations (
		category integer not null,
		type text not null,
		target text not null default '',
		primary key (category, type, target),
		foreign key (category) references categories(id) on delete cascade
	)""")

	mochi.db.execute("""create table if not exists push_pending (
		account integer not null,
		event_id text not null,
		subscription text not null,
		payload text not null,
		created integer not null,
		primary key (account, event_id)
	)""")
	mochi.db.execute("create index if not exists push_pending_created on push_pending(account, created)")

	_seed_categories()

def _seed_categories():
	now = mochi.time.now()
	if not mochi.db.exists("select 1 from categories where id = 0"):
		mochi.db.execute("insert into categories (id, label, created) values (0, 'No notifications', ?)", now)
	normal_id = _ensure_category("Normal", now)
	# Ensure exactly one default exists (Normal by default)
	if not mochi.db.exists('select 1 from categories where "default" = 1'):
		mochi.db.execute('update categories set "default" = 1 where id = ?', normal_id)
	# Normal: web + every notify-by-default account + every notify-by-default RSS feed
	if not mochi.db.exists("select 1 from destinations where category = ?", normal_id):
		mochi.db.execute("insert into destinations (category, type, target) values (?, 'web', '')", normal_id)
		for acc in mochi.account.list("notify") or []:
			if acc.get("enabled"):
				mochi.db.execute("insert or ignore into destinations (category, type, target) values (?, 'account', ?)", normal_id, str(acc["id"]))
		for feed in mochi.db.rows("select id from rss where enabled = 1") or []:
			mochi.db.execute("insert or ignore into destinations (category, type, target) values (?, 'rss', ?)", normal_id, feed["id"])

def _ensure_category(label, now):
	existing = mochi.db.row("select id from categories where label = ?", label)
	if existing:
		return existing["id"]
	mochi.db.execute("insert into categories (label, created) values (?, ?)", label, now)
	return mochi.db.row("select last_insert_rowid() as id")["id"]

def database_upgrade(to_version):
	if to_version == 9:
		tables = [r["name"] for r in mochi.db.rows("select name from sqlite_master where type='table'")]
		if "rss" not in tables:
			mochi.db.execute("""create table if not exists rss (
				id text primary key,
				name text not null,
				token text not null unique,
				created integer not null,
				enabled integer not null default 1
			)""")
		if "subscriptions" not in tables:
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
		if "destinations" not in tables:
			mochi.db.execute("""create table if not exists destinations (
				subscription integer not null,
				type text not null,
				target text not null,
				primary key (subscription, type, target),
				foreign key (subscription) references subscriptions(id) on delete cascade
			)""")

	if to_version == 10:
		# Notification categories redesign:
		#   - Rename notifications.category → topic (used as aggregation key)
		#   - New `categories` table (id=0 reserved for "No notifications")
		#   - `destinations` repointed from subscription → category
		#   - `subscriptions` (app, topic, object) + category FK, unique index
		#   - Existing subscriptions dropped (apps re-prompt on next visit)
		now = mochi.time.now()

		# Rename notifications.category → topic
		mochi.db.execute("alter table notifications rename column category to topic")

		# Categories table
		mochi.db.execute("""create table categories (
			id integer primary key,
			label text not null,
			"default" integer not null default 0,
			created integer not null
		)""")
		mochi.db.execute("insert into categories (id, label, created) values (0, 'No notifications', ?)", now)
		normal_id = _ensure_category("Normal", now)
		mochi.db.execute('update categories set "default" = 1 where id = ?', normal_id)

		# Destinations (fresh start)
		mochi.db.execute("drop table if exists destinations")
		mochi.db.execute("""create table destinations (
			category integer not null,
			type text not null,
			target text not null default '',
			primary key (category, type, target),
			foreign key (category) references categories(id) on delete cascade
		)""")
		mochi.db.execute("insert into destinations (category, type, target) values (?, 'web', '')", normal_id)
		for acc in mochi.account.list("notify") or []:
			if acc.get("enabled"):
				mochi.db.execute("insert or ignore into destinations (category, type, target) values (?, 'account', ?)", normal_id, str(acc["id"]))
		for feed in mochi.db.rows("select id from rss where enabled = 1") or []:
			mochi.db.execute("insert or ignore into destinations (category, type, target) values (?, 'rss', ?)", normal_id, feed["id"])

		# Subscriptions (fresh start — apps re-prompt on next visit)
		mochi.db.execute("drop table subscriptions")
		mochi.db.execute("""create table subscriptions (
			id integer primary key,
			app text not null,
			topic text not null default '',
			object text not null default '',
			label text not null,
			category integer,
			created integer not null
		)""")
		mochi.db.execute("create unique index subscriptions_app_topic_object on subscriptions(app, topic, object)")

	if to_version == 11:
		# Notifications redesign: drop the explicit subscribe step. Apps no longer
		# call subscribe/reconcile; the row in `topics` is created lazily on first
		# send with the user's default category. The subscriptions table is renamed
		# to `topics` and dropped + recreated (handful of users, all on Normal).
		mochi.db.execute("drop table if exists subscriptions")
		mochi.db.execute("""create table topics (
			id integer primary key,
			app text not null,
			topic text not null default '',
			object text not null default '',
			label text not null,
			category integer,
			created integer not null
		)""")
		mochi.db.execute("create unique index topics_app_topic_object on topics(app, topic, object)")

	if to_version == 12:
		# Add `sender` column so notifications can show the originating user's
		# avatar (entity ID of the inviter / commenter / message author).
		# Originally used mochi.db.rows("pragma table_info(...)") which is blocked
		# by api_db_query — that errored out (and emailed the admin) every time
		# this migration ran. mochi.db.table() is the supported wrapper.
		cols = [r["name"] for r in mochi.db.table("notifications")]
		if "sender" not in cols:
			mochi.db.execute("alter table notifications add column sender text not null default ''")

	if to_version == 13:
		# Re-apply v12 for DBs whose schema bumped past 12 with the column
		# never actually being added (the version bumps even on error).
		cols = [r["name"] for r in mochi.db.table("notifications")]
		if "sender" not in cols:
			mochi.db.execute("alter table notifications add column sender text not null default ''")

	if to_version == 14:
		# Server-side queue for undelivered unifiedpush events. When the on-device
		# distributor's WebSocket isn't subscribed (phone killed by OEM, Doze drop,
		# transient network), websockets_send is a no-op and the event would be
		# lost. function_send writes a row here before notify; the phone drains it
		# over HTTP after each WS resubscribe. Bounded by 7-day TTL only, no count
		# cap.
		mochi.db.execute("""create table if not exists push_pending (
			account integer not null,
			event_id text not null,
			subscription text not null,
			payload text not null,
			created integer not null,
			primary key (account, event_id)
		)""")
		mochi.db.execute("create index if not exists push_pending_created on push_pending(account, created)")

	if to_version == 15:
		# Re-apply v14 for DBs whose schema bumped past 14 with the table never
		# actually being created (a string-concat parse error in 3.7's first
		# build aborted the whole file at load time; the schema version still
		# bumped per the server's "bump even on error" rule). Idempotent for
		# DBs where v14 did succeed.
		tables = [r["name"] for r in mochi.db.rows("select name from sqlite_master where type='table'")]
		if "push_pending" not in tables:
			mochi.db.execute("""create table if not exists push_pending (
				account integer not null,
				event_id text not null,
				subscription text not null,
				payload text not null,
				created integer not null,
				primary key (account, event_id)
			)""")
			mochi.db.execute("create index if not exists push_pending_created on push_pending(account, created)")

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
	mochi.websocket.write("notifications", {"type": "clear_object", "app": app, "object": object})

def function_list(context):
	return mochi.db.rows("select * from notifications order by created")

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

def _badge_count():
	row = mochi.db.row("select count(*) as count, coalesce(sum(count), 0) as total from notifications where read = 0")
	return {"count": row["count"] if row else 0, "total": row["total"] if row else 0}

def action_list(a):
	function_expire({})
	rows = function_list({})
	counts = _badge_count()

	version = mochi.server.version()
	rss_supported = version_gte(version, "0.3")

	return {
		"data": rows,
		"count": counts["count"],
		"total": counts["total"],
		"rss": rss_supported
	}

def action_count(a):
	return {"data": _badge_count()}

def action_read(a):
	id = a.input("id", "").strip()
	if not id or len(id) > 64:
		a.error.label(400, "errors.invalid_id")
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
	if not a.user:
		a.error.label(401, "errors.authentication_required")
		return

	feed_name = "Notifications"
	feed_token = a.input("token", "").strip()
	if feed_token:
		feed = mochi.db.row("select name from rss where token = ?", feed_token)
		if feed:
			feed_name = feed["name"]

	function_expire({})

	rows = mochi.db.rows("""
		select id, app, topic, content, link, count, created
		from notifications order by created desc limit 100
	""")

	all_apps = mochi.app.list()
	app_names = {}
	for app in all_apps:
		app_names[app["id"]] = app["name"]
		for path in app.get("paths", []):
			app_names[path] = app["name"]
	server_name = mochi.app.label("notifications.app.server")

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
		if row["app"] == "":
			app_name = server_name
		else:
			app_name = app_names.get(row["app"], row["app"])
		title = app_name + ": " + row["topic"]
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

# Connected accounts endpoints (thin wrappers around mochi.account.* API)

def action_accounts_providers(a):
	capability = a.input("capability")
	return {"data": mochi.account.providers(capability)}

def action_accounts_list(a):
	capability = a.input("capability")
	return {"data": mochi.account.list(capability)}

def action_accounts_get(a):
	id = a.input("id", "").strip()
	if not id or not id.isdigit():
		a.error.label(400, "errors.invalid_id")
		return
	result = mochi.account.get(int(id))
	return {"data": result}

def action_accounts_add(a):
	type = a.input("type")
	if not type:
		a.error.label(400, "errors.type_is_required")
		return

	fields = {}
	for key in ["label", "address", "token", "api_key", "url", "endpoint", "auth", "p256dh", "secret", "topic", "server"]:
		val = a.input(key)
		if val:
			if len(val) > 4096:
				a.error(400, key + " is too long")
				return
			fields[key] = val

	notify_default = a.input("notify_default", "1")
	notify_default = notify_default == "1" or notify_default == "true"

	result = mochi.account.add(type, **fields)

	if result and result.get("id"):
		account_id = result["id"]
		mochi.account.update(account_id, enabled=notify_default)
		# If flagged notify-by-default, add as destination to every existing category (except id 0)
		if notify_default:
			_add_destination_to_categories("account", str(account_id))

	return {"data": result}

def action_accounts_update(a):
	id = a.input("id", "").strip()
	if not id or not id.isdigit():
		a.error.label(400, "errors.invalid_id")
		return

	fields = {}
	label = a.input("label")
	if label != None:
		fields["label"] = label

	result = mochi.account.update(int(id), **fields)
	return {"data": result}

def action_accounts_remove(a):
	id = a.input("id", "").strip()
	if not id or not id.isdigit():
		a.error.label(400, "errors.invalid_id")
		return

	# Also remove from all categories' destinations
	mochi.db.execute("delete from destinations where type = 'account' and target = ?", id)
	result = mochi.account.remove(int(id))
	return {"data": result}

def action_accounts_verify(a):
	id = a.input("id", "").strip()
	if not id or not id.isdigit():
		a.error.label(400, "errors.invalid_id")
		return

	code = a.input("code", "").strip()
	if not code or len(code) > 256:
		a.error.label(400, "errors.invalid_code")
		return
	result = mochi.account.verify(int(id), code)
	return {"data": result}

def action_accounts_vapid(a):
	key = mochi.webpush.key()
	if not key:
		return a.error.label(503, "errors.push_notifications_not_available")
	return {"data": {"key": key}}

def _add_destination_to_categories(type, target):
	# Add this destination to every category except id 0 (No notifications)
	cats = mochi.db.rows("select id from categories where id != 0")
	for c in cats or []:
		mochi.db.execute(
			"insert or ignore into destinations (category, type, target) values (?, ?, ?)",
			c["id"], type, target
		)

# RSS feed management endpoints

def action_rss_list(a):
	rows = mochi.db.rows("select id, name, token, created, enabled from rss order by created desc")
	return {"data": rows or []}

def action_rss_create(a):
	name = (a.input("name") or "RSS feed").strip()
	if len(name) > 100:
		return a.error.label(400, "errors.feed_name_is_too_long")
	if not name:
		return a.error.label(400, "errors.feed_name_is_required")

	notify_default = a.input("notify_default", "1")
	notify_default = notify_default == "1" or notify_default == "true"

	id = mochi.uid()
	token = mochi.token.create("rss:" + id, ["rss"])
	if not token:
		return a.error.label(500, "errors.failed_to_create_token")
	now = mochi.time.now()

	enabled = 1 if notify_default else 0
	mochi.db.execute("insert into rss (id, name, token, created, enabled) values (?, ?, ?, ?, ?)", id, name, token, now, enabled)

	if notify_default:
		_add_destination_to_categories("rss", id)

	return {"data": {"id": id, "name": name, "token": token, "created": now, "enabled": enabled}}

def action_rss_delete(a):
	id = a.input("id", "").strip()
	if not id or len(id) > 64:
		return a.error.label(400, "errors.invalid_id")

	exists = mochi.db.exists("select 1 from rss where id = ?", id)
	if not exists:
		return a.error.label(404, "errors.feed_not_found")

	token_name = "rss:" + id
	for token in mochi.token.list():
		if token.get("name") == token_name:
			mochi.token.delete(token["hash"])
			break

	mochi.db.execute("delete from destinations where type = 'rss' and target = ?", id)
	mochi.db.execute("delete from rss where id = ?", id)
	return {"data": {}}

def action_rss_rename(a):
	return action_rss_update(a)

def action_rss_update(a):
	id = a.input("id", "").strip()
	if not id or len(id) > 64:
		return a.error.label(400, "errors.invalid_id")

	exists = mochi.db.exists("select 1 from rss where id = ?", id)
	if not exists:
		return a.error.label(404, "errors.feed_not_found")

	name = a.input("name", "").strip()
	if name:
		if len(name) > 100:
			return a.error.label(400, "errors.feed_name_is_too_long")
		mochi.db.execute("update rss set name = ? where id = ?", name, id)

	enabled = a.input("enabled", "").strip()
	if enabled:
		enabled_val = 1 if enabled == "1" else 0
		mochi.db.execute("update rss set enabled = ? where id = ?", enabled_val, id)

	return {"data": {}}

# Topic service functions

def function_send(context, topic, object="", title="", body="", url="", label="", sender="", count=None):
	"""Send a notification from the calling app.

	Topics are keyed by (app, topic, object) and created lazily. On first send
	for a given key, a topic row is inserted with the user's default category.
	Subsequent sends look up the row's category and route accordingly. The
	caller passes a human-readable `label` resolved from its own labels (so the
	settings UI can group and display topics in the user's language); the
	stored label is refreshed on every send to track language changes.

	Routing:
	  1. Topic row's category = 0 ("No notifications") → drop entirely.
	  2. Topic row's category is NULL (no default category exists) → web-only.
	  3. Otherwise → fan out to the category's destinations.

	count: optional override on the badge counter:
	  None (default) — increment by 1 when rolling up an unread row, set to 1
	                   on insert. Existing behaviour. Suits chat / feeds /
	                   posts where count = unread items.
	  <integer>      — force count to this value on both rollup and insert.
	                   Pass count=1 for state-style notifications (e.g. server
	                   upgrade alerts) where the latest version is a state,
	                   not an item count.

	The reserved app id "" is only accepted when the call originates from the
	Mochi server itself (the core-only service_call_as_server helper sets
	context["_server"]=True). Apps calling through mochi.service.call always
	have their own app id in context, so this can't be spoofed.
	"""
	app = context.get("app", "")
	if not app and not context.get("_server", False):
		return 0
	if not title or not body:
		return 0

	row = mochi.db.row(
		"select id, label, category from topics where app = ? and topic = ? and object = ?",
		app, topic, object
	)
	if not row:
		default = mochi.db.row('select id from categories where "default" = 1')
		cat_val = default["id"] if default else None
		mochi.db.execute(
			"insert into topics (app, topic, object, label, category, created) values (?, ?, ?, ?, ?, ?)",
			app, topic, object, label, cat_val, mochi.time.now()
		)
		category = cat_val
	else:
		category = row["category"]
		# Refresh the stored label if the caller passed one and it differs
		# (handles language switches and per-app label updates).
		if label and label != row["label"]:
			mochi.db.execute(
				"update topics set label = ? where id = ?",
				label, row["id"]
			)

	# id 0 = No notifications: drop
	if category == 0:
		return 0

	content = title + ": " + body

	# No default category configured: web-only fallback.
	if category == None:
		_deliver_web(app, topic, object, title, body, url, content, sender, count)
		return 1

	dests = mochi.db.rows(
		"select type, target from destinations where category = ?",
		int(category)
	)
	delivered = 0
	for dest in dests or []:
		if dest["type"] == "web":
			_deliver_web(app, topic, object, title, body, url, content, sender, count)
			delivered += 1
		elif dest["type"] == "account":
			account_id = int(dest["target"])
			_push_queue_if_unifiedpush(account_id, app, topic, object, title, body, url)
			mochi.account.notify(
				account=account_id,
				app=app,
				category=topic,
				object=object,
				title=title,
				body=body,
				link=url
			)
			delivered += 1
		# rss destinations are queried on demand, no active delivery
	return delivered

def _deliver_web(app, topic, object, title, body, url, content, sender="", count=None):
	now = mochi.time.now()
	existing = mochi.db.row(
		"select * from notifications where app = ? and topic = ? and object = ?",
		app, topic, object
	)

	if existing and existing["read"] == 0:
		new_count = count if count != None else existing["count"] + 1
		mochi.db.execute(
			"update notifications set content = ?, count = ?, created = ?, sender = ? where id = ?",
			content, new_count, now, sender, existing["id"]
		)
		notif_id = existing["id"]
		ws_content = content
		ws_count = new_count
	else:
		notif_id = mochi.uid()
		new_count = count if count != None else 1
		mochi.db.execute(
			"""replace into notifications (id, app, topic, object, content, link, sender, count, created, read)
			values (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)""",
			notif_id, app, topic, object, content, url, sender, new_count, now
		)
		ws_content = content
		ws_count = new_count

	mochi.websocket.write("notifications", {
		"type": "new",
		"id": notif_id,
		"app": app,
		"topic": topic,
		"object": object,
		"content": ws_content,
		"link": url,
		"count": ws_count,
		"created": now,
		"read": 0,
	})

def function_topics(context, object=None):
	"""List topic rows belonging to the calling app."""
	app = context.get("app", "")
	if not app:
		return []
	if object != None:
		return mochi.db.rows("select * from topics where app = ? and object = ?", app, object) or []
	return mochi.db.rows("select * from topics where app = ?", app) or []

def function_topic_remove(context, id):
	"""Remove a topic row belonging to the calling app."""
	app = context.get("app", "")
	if not app or not id:
		return False

	exists = mochi.db.exists(
		"select 1 from topics where id = ? and app = ?",
		id, app
	)
	if not exists:
		return False

	mochi.db.execute("delete from topics where id = ?", id)
	return True

# Permission-gated function for apps to list categories (for pickers shown in app UI).
# Kept narrow — only labels and ids, no destinations.
def function_categories(context):
	return mochi.db.rows('select id, label, "default" from categories order by id') or []

# Category CRUD — used by the settings page (no permission gate; user-owned data)

def function_category_list(context):
	cats = mochi.db.rows('select id, label, "default", created from categories order by id') or []
	result = []
	for c in cats:
		dests = mochi.db.rows("select type, target from destinations where category = ?", c["id"]) or []
		c["destinations"] = dests
		result.append(c)
	return result

def function_category_create(context, label="", destinations=None, default=None):
	if not label or not mochi.text.valid(label, "text"):
		return None
	now = mochi.time.now()
	mochi.db.execute("insert into categories (label, created) values (?, ?)", label, now)
	cid = mochi.db.row("select last_insert_rowid() as id")["id"]
	_apply_destinations(cid, destinations)
	if default:
		_set_default(cid)
	return cid

def _set_default(id):
	# Enforce exactly-one-default invariant. id=0 (No notifications) can't be default.
	if not id or id == 0:
		return
	mochi.db.execute('update categories set "default" = 0')
	mochi.db.execute('update categories set "default" = 1 where id = ?', id)

def function_category_update(context, id=0, label=None, destinations=None, default=None):
	if not id:
		return False
	if not mochi.db.exists("select 1 from categories where id = ?", id):
		return False
	if label != None:
		if not mochi.text.valid(label, "text"):
			return False
		mochi.db.execute("update categories set label = ? where id = ?", label, id)
	if default != None and id != 0:
		# Only allow setting default on (can't unset without picking another).
		if default:
			_set_default(id)
	if destinations != None and id != 0:
		_apply_destinations(id, destinations)
	return True

def function_category_delete(context, id=0, reassign_to=None):
	"""Delete a category, reassigning any topic rows to `reassign_to`.

	reassign_to must be the id of another existing category. Use 0 for No notifications.
	Category 0 itself cannot be deleted.
	"""
	if not id or id == 0:
		return False
	if not mochi.db.exists("select 1 from categories where id = ?", id):
		return False
	if reassign_to == None:
		return False
	if not mochi.db.exists("select 1 from categories where id = ?", int(reassign_to)):
		return False
	if int(reassign_to) == int(id):
		return False
	# If we're deleting the default, promote the reassign target to be the new
	# default (can't leave the system without a default).
	was_default = mochi.db.exists('select 1 from categories where id = ? and "default" = 1', id)
	mochi.db.execute("update topics set category = ? where category = ?", int(reassign_to), id)
	mochi.db.execute("delete from destinations where category = ?", id)
	mochi.db.execute("delete from categories where id = ?", id)
	if was_default:
		_set_default(int(reassign_to))
	return True

def function_category_test(context, id=0):
	"""Send a test notification through the category's destinations.

	External destinations (accounts) are invoked via mochi.account.notify. A
	bell entry is always written so the user gets immediate visible feedback
	that the test fired, even when 'web' is not among the configured
	destinations — otherwise a stale row from a previous test could persist
	and look like the most recent click landed nothing fresh.
	"""
	if not id:
		return {"sent": 0, "web": False}
	cat = mochi.db.row("select label from categories where id = ?", id)
	if not cat:
		return {"sent": 0, "web": False}
	dests = mochi.db.rows("select type, target from destinations where category = ?", id) or []
	sent = 0
	web = False
	title = mochi.app.label("notifications.body.test")
	body_web = mochi.app.label("notifications.body.test_via_web")
	_deliver_web("notifications", "test", str(id), title, body_web, "/settings/user/notifications", title + ": " + body_web)
	for dest in dests:
		if dest["type"] == "web":
			web = True
			sent += 1
		elif dest["type"] == "account":
			account_id = int(dest["target"])
			account_label = _account_display_label(account_id)
			if not account_label:
				continue  # stale destination row pointing at a deleted account
			body = mochi.app.label("notifications.body.test_via_account", account=account_label)
			_push_queue_if_unifiedpush(account_id, "notifications", "test", "", title, body, "")
			mochi.account.notify(
				account=account_id,
				app="notifications",
				category="test",
				object="",
				title=title,
				body=body,
				link=""
			)
			sent += 1
	return {"sent": sent, "web": web}

def _account_display_label(account_id):
	"""Friendly name for a connected account, for test-notification bodies.
	Prefers the user-set label, falls back to a provider-typed string.
	Returns "" when the account row no longer exists (stale destinations
	pointing at deleted accounts)."""
	acc = mochi.account.get(account_id)
	if not acc:
		return ""
	label = acc.get("label", "")
	if label:
		return label
	t = acc.get("type", "")
	if t == "fcm":
		return mochi.app.label("notifications.account.fcm")
	if t == "unifiedpush":
		return mochi.app.label("notifications.account.unifiedpush")
	if t == "email":
		return acc.get("identifier", "") or mochi.app.label("notifications.account.email")
	if t == "browser":
		return mochi.app.label("notifications.account.browser")
	if t == "pushbullet":
		return mochi.app.label("notifications.account.pushbullet")
	if t == "ntfy":
		return mochi.app.label("notifications.account.ntfy")
	if t == "url":
		return mochi.app.label("notifications.account.url")
	return t

def _apply_destinations(category_id, destinations):
	if destinations == None:
		return
	if category_id == 0:
		return
	mochi.db.execute("delete from destinations where category = ?", category_id)
	for dest in destinations:
		dest_type = dest.get("type", "")
		dest_target = dest.get("target", "")
		if not dest_type:
			continue
		mochi.db.execute(
			"insert or ignore into destinations (category, type, target) values (?, ?, ?)",
			category_id, dest_type, str(dest_target)
		)

# Topic helpers — used by settings page and notification dropdown

def function_topic_list(context):
	"""List every topic row with app name and object name resolved."""
	rows = mochi.db.rows("select * from topics order by created desc") or []
	if not rows:
		return []
	all_apps = mochi.app.list()
	app_names = {}
	for app in all_apps:
		app_names[app["id"]] = app["name"]
		for path in app.get("paths", []):
			app_names[path] = app["name"]
	server_name = mochi.app.label("notifications.app.server")
	result = []
	for row in rows:
		if row["app"] == "":
			row["app_name"] = server_name
		else:
			row["app_name"] = app_names.get(row["app"], row["app"].capitalize())
		if row["object"] and mochi.text.valid(row["object"], "entity"):
			row["object_name"] = mochi.entity.name(row["object"]) or ""
		else:
			row["object_name"] = ""
		result.append(row)
	return result

def function_topic_set_category(context, id=0, category=None):
	if not id:
		return False
	if not mochi.db.exists("select 1 from topics where id = ?", id):
		return False
	if category == None:
		mochi.db.execute("update topics set category = null where id = ?", id)
	else:
		if not mochi.db.exists("select 1 from categories where id = ?", int(category)):
			return False
		mochi.db.execute("update topics set category = ? where id = ?", int(category), id)
	return True

def function_topic_lookup(context, app="", topic="", object=""):
	"""Find the topic row matching (app, topic, object) for the per-notification picker.
	Returns the row with category, or None if no row exists yet."""
	if not app:
		return None
	return mochi.db.row(
		"select id, app, topic, object, label, category from topics where app = ? and topic = ? and object = ?",
		app, topic, object
	)

def function_topic_delete(context, id=0):
	"""Delete any topic row by id. Used by the settings page."""
	if not id:
		return False
	if not mochi.db.exists("select 1 from topics where id = ?", id):
		return False
	mochi.db.execute("delete from topics where id = ?", id)
	return True

def function_destinations_available(context):
	"""Return the full set of available destinations plus their 'notify by default' flags.
	Used by the settings UI to build the category editor grid."""
	accounts = mochi.account.list("notify") or []
	feeds = mochi.db.rows("select id, name, enabled from rss") or []
	return {"accounts": accounts, "feeds": feeds}

# HTTP action endpoints (settings page calls these via service proxy; kept for direct use too)

def action_categories_list(a):
	return {"data": function_category_list({})}

def action_categories_create(a):
	label = a.input("label", "").strip()
	if not label:
		return a.error.label(400, "errors.label_is_required")
	default_raw = a.input("default", "")
	default = 1 if default_raw == "1" or default_raw == "true" else None
	destinations_json = a.input("destinations", "").strip()
	destinations = json.decode(destinations_json) if destinations_json else None
	cid = function_category_create({}, label, destinations, default)
	if not cid:
		return a.error.label(400, "errors.invalid_category")
	return {"data": {"id": cid}}

def action_categories_update(a):
	id = a.input("id", "").strip()
	if not id or not id.isdigit():
		return a.error.label(400, "errors.invalid_id")
	label = a.input("label")
	default_raw = a.input("default")
	destinations_json = a.input("destinations", "").strip()
	default = None
	if default_raw != None and default_raw != "":
		default = 1 if default_raw == "1" or default_raw == "true" else 0
	destinations = json.decode(destinations_json) if destinations_json else None
	ok = function_category_update({}, int(id), label, destinations, default)
	if not ok:
		return a.error.label(404, "errors.not_found")
	return {"data": {}}

def action_categories_delete(a):
	id = a.input("id", "").strip()
	reassign = a.input("reassign_to", "").strip()
	if not id or not id.isdigit():
		return a.error.label(400, "errors.invalid_id")
	if not reassign or not reassign.lstrip("-").isdigit():
		return a.error.label(400, "errors.reassign_to_is_required")
	ok = function_category_delete({}, int(id), int(reassign))
	if not ok:
		return a.error.label(400, "errors.could_not_delete")
	return {"data": {}}

def action_categories_test(a):
	id = a.input("id", "").strip()
	if not id or not id.isdigit():
		return a.error.label(400, "errors.invalid_id")
	return {"data": function_category_test({}, int(id))}

def action_topics_list(a):
	return {"data": function_topic_list({})}

def action_topics_set_category(a):
	id = a.input("id", "").strip()
	if not id or not id.isdigit():
		return a.error.label(400, "errors.invalid_id")
	cat_raw = a.input("category", "")
	category = None
	if cat_raw != "" and cat_raw.lstrip("-").isdigit():
		category = int(cat_raw)
	ok = function_topic_set_category({}, int(id), category)
	if not ok:
		return a.error.label(404, "errors.not_found")
	return {"data": {}}

def action_topics_lookup(a):
	"""Find the topic row matching (app, topic, object) for the dropdown picker."""
	app = a.input("app", "").strip()
	topic = a.input("topic", "").strip()
	object = a.input("object", "").strip()
	if not app:
		return a.error.label(400, "errors.app_is_required")
	row = function_topic_lookup({}, app, topic, object)
	return {"data": row}

def action_topics_delete(a):
	id = a.input("id", "").strip()
	if not id or not id.isdigit():
		return a.error.label(400, "errors.invalid_id")
	if not mochi.db.exists("select 1 from topics where id = ?", int(id)):
		return a.error.label(404, "errors.topic_not_found")
	mochi.db.execute("delete from topics where id = ?", int(id))
	return {"data": {}}

def action_destinations_list(a):
	return {"data": function_destinations_available({})}

# Service functions for account management (permission-gated)

def function_accounts_vapid(context):
	key = mochi.webpush.key()
	return {"key": key or ""}

def function_accounts_list(context, capability=""):
	return mochi.account.list(capability) or []

def function_accounts_add(context, type="", **fields):
	if not type:
		return None
	result = mochi.account.add(type, **fields)
	if result and result.get("id"):
		account_id = result["id"]
		mochi.account.update(account_id, enabled=True)
		_add_destination_to_categories("account", str(account_id))
	return result

def function_accounts_remove(context, id=0):
	if not id:
		return None
	mochi.db.execute("delete from destinations where type = 'account' and target = ?", str(id))
	return mochi.account.remove(id)

# UnifiedPush registration. The Mochi Android distributor calls this when a user
# picks it as their UP distributor. Two cases:
#   - Local case (endpoint=""): server allocates a path that the distributor will
#     concatenate with its known server URL to form the absolute endpoint. The
#     distributor stores the matching private p256dh half on-device.
#   - Foreign case (endpoint set, e.g. ntfy.sh URL): the user picked a third-
#     party distributor. We just store the foreign endpoint and POST RFC 8030
#     to it at delivery time — endpoint is opaque to us.
def function_push_register(context, label="", auth="", p256dh="", endpoint=""):
	if not auth or not p256dh:
		return None

	fields = {"auth": auth, "p256dh": p256dh}
	if label:
		fields["label"] = label

	if endpoint:
		fields["endpoint"] = endpoint
	else:
		# Local case: path-only endpoint, distributor prepends server URL.
		# Account ID is filled in below; we also need an unguessable token so
		# the inbound endpoint (when implemented) can't be brute-forced.
		fields["endpoint"] = ""

	result = mochi.account.add("unifiedpush", **fields)
	if not result or not result.get("id"):
		return result

	account_id = result["id"]

	# Local case: now that we have the account ID, write the canonical path back.
	# Inbound endpoint will be /menu/-/push/inbound/<account_id> guarded by
	# the on-device p256dh keypair (only the matching distributor can decrypt).
	if not endpoint:
		path = "/menu/-/push/inbound/%d" % account_id
		mochi.account.update(account_id, endpoint=path)
		result["endpoint"] = path

	mochi.account.update(account_id, enabled=True)
	_add_destination_to_categories("account", str(account_id))
	return result

# function_push_register_fcm stores an FCM device token for this user, keyed
# by the Firebase Installations ID (FID). The server-side `case "fcm"` in
# api_account_add does the upsert: token refreshes update the existing row
# in place, and a second phone (different FID) creates a separate row so
# both devices receive pushes. The row id is stable, so destinations rows
# pointing at it survive token refreshes.
def function_push_register_fcm(context, token="", install_id="", device=""):
	if not token or not install_id:
		return None
	kwargs = {"token": token, "install_id": install_id}
	if device:
		kwargs["label"] = device
	result = mochi.account.add("fcm", **kwargs)
	if not result or not result.get("id"):
		return result
	account_id = result["id"]
	mochi.account.update(account_id, enabled=True)
	_add_destination_to_categories("account", str(account_id))
	return result

# function_push_setup tells the client which push transport this server uses.
# When the admin has pasted Firebase config into system settings, returns
# {"transport": "fcm", "firebase_config": {project_id, app_id, api_key,
# messaging_sender_id}} and the client initialises Firebase Messaging
# against it. Otherwise returns {"transport": "unifiedpush"} and the client
# falls back to the UnifiedPush distributor.
#
# Accepts two paste formats so the admin can drop whichever file Firebase
# Console gave them:
#   1. google-services.json verbatim — has project_info.{project_id,
#      project_number} + client[0].client_info.mobilesdk_app_id +
#      client[0].api_key[0].current_key
#   2. A flat {project_id, app_id, api_key, messaging_sender_id} JSON.
# Both reduce to the same four-field response.
def function_push_setup(context):
	config_raw = mochi.setting.get("fcm.firebase_config")
	if not config_raw:
		return {"transport": "unifiedpush"}
	config = json.decode(config_raw)
	if type(config) != "dict":
		return {"transport": "unifiedpush"}
	extracted = _extract_firebase_config(config)
	if not extracted:
		return {"transport": "unifiedpush"}
	return {"transport": "fcm", "firebase_config": extracted}

def _extract_firebase_config(raw):
	"""Return {project_id, app_id, api_key, messaging_sender_id} from either
	a google-services.json or a flat config dict, or None if neither
	yields all four required fields."""
	project_info = raw.get("project_info")
	clients = raw.get("client")
	if type(project_info) == "dict" and type(clients) == "list" and len(clients) > 0:
		# google-services.json shape.
		client = clients[0]
		client_info = client.get("client_info", {}) if type(client) == "dict" else {}
		api_keys = client.get("api_key", []) if type(client) == "dict" else []
		api_key = ""
		if type(api_keys) == "list" and len(api_keys) > 0 and type(api_keys[0]) == "dict":
			api_key = api_keys[0].get("current_key", "")
		out = {
			"project_id": project_info.get("project_id", ""),
			"messaging_sender_id": project_info.get("project_number", ""),
			"app_id": client_info.get("mobilesdk_app_id", "") if type(client_info) == "dict" else "",
			"api_key": api_key,
		}
	else:
		# Flat shape — accept either snake_case or sender_id alias.
		out = {
			"project_id": raw.get("project_id", ""),
			"messaging_sender_id": raw.get("messaging_sender_id", raw.get("sender_id", "")),
			"app_id": raw.get("app_id", ""),
			"api_key": raw.get("api_key", ""),
		}
	for k in ("project_id", "messaging_sender_id", "app_id", "api_key"):
		if not out.get(k):
			return None
	return out

# Inbound RFC 8030 push from a third-party Application Server (e.g. Mastodon
# whose user picked the Mochi distributor). Forwards the opaque encrypted body
# to the device via the existing WebSocket fast-path. Deferred — the primary
# use case (Mochi-server-to-its-own-users) doesn't need this.
def function_push_inbound(context, account_id=0, payload=""):
	if not account_id:
		return {"ok": False, "error": "missing account_id"}
	# TODO: forward via mochi.websocket.write once the Go side exposes a
	# binary-safe write (current API is JSON text only).
	return {"ok": False, "error": "inbound endpoint not yet implemented"}

# _push_queue_if_unifiedpush writes a pending row to push_pending if the account
# is a local-distributor unifiedpush subscription. Called from function_send
# alongside the live mochi.account.notify attempt — the WS event is the fast
# happy-path; this row is the durable backstop for when the on-device WebSocket
# isn't subscribed (phone killed by OEM, Doze drop, transient network). On
# subscribe the phone drains rows over /menu/-/push/drain, acks via
# /menu/-/push/ack, and matching rows here are deleted.
#
# Foreign-endpoint unifiedpush accounts (ntfy etc) are excluded — third-party
# Application Servers handle their own retry. Other account types (email,
# pushbullet, browser, url) also have their own server-side retry semantics.
def _push_queue_if_unifiedpush(account_id, app, topic, object, title, body, url):
	acc = mochi.account.get(account_id)
	if not acc or acc.get("type") != "unifiedpush":
		return
	# identifier holds the endpoint (api_account_add stores endpoint there
	# for unifiedpush). Absolute URLs are foreign distributors (ntfy etc) —
	# they have their own retry path, no queuing needed. Path-only endpoints
	# are our local distributor, the case the queue exists for.
	identifier = acc.get("identifier", "")
	if not identifier or identifier.startswith("http"):
		return
	subscription = identifier.split("/")[-1]

	# Match the WS payload shape so the phone treats drained events identically
	# to live ones (same RFC 8030 body fields).
	payload = json.encode({
		"title": title,
		"body": body,
		"link": url,
		"tag": app + "-" + topic + "-" + object,
	})
	event_id = app + "-" + topic + "-" + object

	# Same logical push hitting the queue twice (multi-replica fan-out, or
	# repeat updates to the same coalesced thread) becomes one row with the
	# latest payload — phone gets the latest content on drain. ON CONFLICT
	# replaces payload + created.
	mochi.db.execute(
		"insert into push_pending (account, event_id, subscription, payload, created) values (?, ?, ?, ?, ?) on conflict(account, event_id) do update set payload=excluded.payload, created=excluded.created",
		account_id, event_id, subscription, payload, mochi.time.now()
	)

# function_push_drain returns pending unifiedpush events for the caller and
# opportunistically sweeps rows older than 7 days. The drain is read-only — the
# phone acks explicitly via function_push_ack after the system notifications
# have been posted, so a phone that crashes mid-drain can re-drain the same
# rows on next subscribe.
def function_push_drain(context):
	now = mochi.time.now()
	# Opportunistic TTL sweep: drop rows older than 7 days, regardless of
	# account or subscriber state. Pattern mirrors the unifiedpush account
	# TTL sweep in api_account_notify (core/server/accounts.go).
	mochi.db.execute(
		"delete from push_pending where created < ?", now - 7 * 86400
	)
	rows = mochi.db.rows(
		"select account, event_id, subscription, payload, created from push_pending order by created"
	) or []
	# Re-shape into the same envelope the WebSocket would deliver, so the
	# phone runs identical code on live and drained events.
	out = []
	for r in rows:
		out.append({
			"subId": r["subscription"],
			"payload": r["payload"],
			"event_id": r["event_id"],
			"account": r["account"],
		})
	return out

# function_push_ack deletes the named rows from the queue. Idempotent — acking
# a row that no longer exists (TTL'd, manually cleared, never queued because
# delivered live first) is a no-op. The phone batches acks per drain or per
# live event.
def function_push_ack(context, account_event_ids=None):
	if not account_event_ids:
		return {"acked": 0}
	acked = 0
	for ae in account_event_ids:
		account = int(ae.get("account", 0))
		event_id = ae.get("event_id", "")
		if not account or not event_id:
			continue
		mochi.db.execute(
			"delete from push_pending where account = ? and event_id = ?",
			account, event_id
		)
		acked += 1
	return {"acked": acked}

# Client-facing action wrappers. Used to live in the menu app
# (/menu/-/push/*); moved here because push is owned by the notifications
# app, not by the menu UI. The menu app retained only the user-menu /
# notifications-tray surface; everything push-transport-related lives here.

def action_push_vapid(a):
	"""Get VAPID key for browser push subscription."""
	result = function_accounts_vapid(None)
	if result == None:
		return a.error.label(503, "errors.push_notifications_not_available")
	return {"data": result}

def action_push_accounts_list(a):
	"""List push accounts."""
	capability = a.input("capability", "")
	return {"data": function_accounts_list(None, capability=capability) or []}

def action_push_accounts_add(a):
	"""Register a browser push account."""
	type = a.input("type", "").strip()
	if not type:
		return a.error.label(400, "errors.type_is_required")
	fields = {}
	for key in ["label", "endpoint", "auth", "p256dh"]:
		val = a.input(key, "")
		if val != "":
			fields[key] = val
	result = function_accounts_add(None, type=type, **fields)
	return {"data": result or {}}

def action_push_accounts_remove(a):
	"""Remove a push account."""
	id = a.input("id", "").strip()
	if not id or not id.isdigit():
		return a.error.label(400, "errors.invalid_id")
	result = function_accounts_remove(None, id=int(id))
	return {"data": result or {}}

def action_push_register(a):
	"""Register a UnifiedPush subscription. Local distributor leaves
	endpoint blank and we synthesise a path; foreign distributor (ntfy
	etc.) passes its own endpoint URL."""
	label = a.input("label", "").strip()
	auth = a.input("auth", "").strip()
	p256dh = a.input("p256dh", "").strip()
	endpoint = a.input("endpoint", "").strip()
	if not auth or not p256dh:
		return a.error.label(400, "errors.invalid_subscription")
	result = function_push_register(None, label=label, auth=auth, p256dh=p256dh, endpoint=endpoint)
	if not result:
		return a.error.label(500, "errors.registration_failed")
	return {"data": result}

def action_push_register_fcm(a):
	"""Register the client's FCM device token. Keyed by Firebase Installations
	ID so token refreshes update the existing row and additional phones
	(different FID) create their own row. Called by the Android client after
	FirebaseMessaging.getToken() returns and again from
	FirebaseMessagingService.onNewToken on refresh."""
	token = a.input("token", "").strip()
	install_id = a.input("install_id", "").strip()
	if not token or not install_id:
		return a.error.label(400, "errors.invalid_subscription")
	device = a.input("device", "").strip()
	result = function_push_register_fcm(None, token=token, install_id=install_id, device=device)
	if not result:
		return a.error.label(500, "errors.registration_failed")
	return {"data": result}

def action_push_setup(a):
	"""Tell the client which push transport this server prefers. Returns
	{"transport": "fcm", "firebase_config": {...}} when the admin has
	pasted Firebase config into system settings, else
	{"transport": "unifiedpush"}. firebase_config is public-by-design."""
	return {"data": function_push_setup(None) or {"transport": "unifiedpush"}}

def action_push_inbound(a):
	"""Receive an RFC 8030 push from an external Application Server.
	Deferred — forwards via WebSocket fast-path once the Go side exposes
	a binary-safe write API. Currently returns 501."""
	return a.error.label(501, "errors.inbound_not_implemented")

def action_push_drain(a):
	"""Return any unifiedpush events that were queued while the on-device
	WebSocket wasn't subscribed (phone killed, Doze drop, network blip).
	Phone calls this immediately after WS subscribe and after each
	foreground entry. Read-only — phone must POST /notifications/-/push/ack
	with the (account, event_id) pairs it actually delivered."""
	return {"data": function_push_drain(None) or []}

def action_push_ack(a):
	"""Delete acknowledged rows from the pending queue. Body: events=<JSON
	array of {account, event_id}>. Idempotent — acking a row that no
	longer exists is a no-op (TTL'd, manually cleared, or never queued
	because of a live race)."""
	events_raw = a.input("events", "")
	if not events_raw:
		return {"data": {"acked": 0}}
	events = json.decode(events_raw)
	if type(events) != "list":
		return a.error.label(400, "errors.invalid_subscription")
	return {"data": function_push_ack(None, account_event_ids=events) or {"acked": 0}}
