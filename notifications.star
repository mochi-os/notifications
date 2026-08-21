# Mochi notifications app
# Copyright © 2026 Mochisoft OÜ
# SPDX-License-Identifier: AGPL-3.0-only
# This file is part of Mochi, licensed under the GNU AGPL v3 with the
# Mochi Application Interface Exception - see license.txt and license-exception.md.

ROW_KEYS = {
	"categories": ["id"],
	"topics": ["app", "topic", "object"],
	"destinations": ["category", "type", "target"],
	"reads": ["app", "topic", "object"],
	"notifications": ["app", "topic", "object"],
}

def row_merge(table, row):
	cols = list(row)
	keys = ROW_KEYS[table]
	fields = [c for c in cols if c not in keys]
	conflict = "do update set " + ", ".join(['"' + c + '"=excluded."' + c + '"' for c in fields]) if fields else "do nothing"
	mochi.db.execute('insert into "' + table + '" (' + ", ".join(['"' + c + '"' for c in cols]) + ") values (" + ", ".join(["?" for c in cols]) + ") on conflict (" + ", ".join(['"' + k + '"' for k in keys]) + ") " + conflict, *[row[c] for c in cols])

# row_set / row_remove take a raw WHERE clause (without the "where" keyword) + args.
def row_set(table, where, args, updates):
	fields = list(updates)
	mochi.db.execute('update "' + table + '" set ' + ", ".join(['"' + c + '"=?' for c in fields]) + " where (" + where + ")", *([updates[c] for c in fields] + list(args)))

def row_remove(table, where, args):
	mochi.db.execute('delete from "' + table + '" where (' + where + ")", *args)

def database_upgrade(version):
	if version == 4:
		# Rebuild push_pending.account as text: under integer affinity an all-digit
		# uid was stored as a number, losing leading zeros, so the text uid the select
		# and delete paths pass never matched.
		mochi.db.execute("""create table if not exists push_pending_new (
			account text not null,
			event_id text not null,
			subscription text not null,
			payload text not null,
			created integer not null,
			primary key (account, event_id)
		)""")
		mochi.db.execute("insert or ignore into push_pending_new ( account, event_id, subscription, payload, created ) select cast(account as text), event_id, subscription, payload, created from push_pending")
		mochi.db.execute("drop table push_pending")
		mochi.db.execute("alter table push_pending_new rename to push_pending")
		mochi.db.execute("create index if not exists push_pending_created on push_pending(account, created)")
	if version == 3:
		# The event that last incremented this row's unread count. A replayed
		# broadcast re-runs notify(), and the roll-up below did count+1 with no
		# memory of what it had already counted, so a resync inflated every
		# unread badge it touched.
		columns = []
		for column in mochi.db.table("notifications"):
			columns.append(column["name"])
		if "last_event" not in columns:
			mochi.db.execute("alter table notifications add column last_event text not null default ''")
	if version == 2:
		# Drop the broadcast tables left in the app data DB when broadcast state moved
		# to the per-app system DB - stale copies mislead diagnosis.
		for table in ["sequence", "log", "acknowledged", "received"]:
			mochi.db.execute("drop table if exists " + table)

def database_create():
	mochi.db.execute("""create table if not exists notifications (
		id text not null primary key,
		app text not null,
		topic text not null,
		object text not null,
		title text not null default '',
		body text not null default '',
		content text not null,
		link text not null default '',
		sender text not null default '',
		count integer not null default 1,
		created integer not null,
		read integer not null default 0,
		fixed integer not null default 0,
		last_event text not null default '',
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
		id text not null primary key,
		label text not null,
		"default" integer not null default 0,
		created integer not null
	)""")

	mochi.db.execute("""create table if not exists topics (
		app text not null,
		topic text not null default '',
		object text not null default '',
		name text not null default '',
		label text not null default '',
		category text,
		created integer not null,
		primary key (app, topic, object)
	)""")

	mochi.db.execute("""create table if not exists destinations (
		category text not null,
		type text not null,
		target text not null default '',
		primary key (category, type, target),
		foreign key (category) references categories(id) on delete cascade
	)""")

	mochi.db.execute("""create table if not exists push_pending (
		account text not null,
		event_id text not null,
		subscription text not null,
		payload text not null,
		created integer not null,
		primary key (account, event_id)
	)""")
	mochi.db.execute("create index if not exists push_pending_created on push_pending(account, created)")

	seed_categories()

def seed_categories():
	now = mochi.time.now()
	# Seed categories are created independently on every host (DB setup runs
	# per-host), so their ids must be DETERMINISTIC and identical everywhere -
	# a per-host mochi.uid() diverges and replicates as duplicate rows. The
	# fixed '0'/'1' ids let every host agree; `insert or ignore` makes the
	# replicated copy a no-op on a host that has already seeded the same id.
	# (User-created categories are single-origin and correctly keep
	# mochi.uid() via function_category_create.)
	mochi.db.execute("insert or ignore into categories (id, label, created) values ('0', 'No notifications', ?)", now)
	# A legacy "Normal" seeded under a uid is kept rather than duplicated.
	existing_normal = mochi.db.row("select id from categories where label = 'Normal'")
	if existing_normal:
		normal_id = existing_normal["id"]
	else:
		normal_id = '1'
		mochi.db.execute("insert or ignore into categories (id, label, created) values ('1', 'Normal', ?)", now)
	# Ensure exactly one default exists (Normal by default)
	if not mochi.db.exists('select 1 from categories where "default" = 1'):
		mochi.db.execute('update categories set "default" = 1 where id = ?', normal_id)
	# Only the web destination is seeded: accounts and feeds join every category
	# when added, and database_create may run without accounts/read, so
	# mochi.account.list() would fail here.
	if not mochi.db.exists("select 1 from destinations where category = ?", normal_id):
		mochi.db.execute("insert or ignore into destinations (category, type, target) values (?, 'web', '')", normal_id)

def function_expire(context):
	now = mochi.time.now()
	mochi.db.execute("delete from notifications where (read = 0 and created < ?) or (read != 0 and created < ?)", now - 30 * 86400, now - 7 * 86400)

def clear_where(where, args):
	mochi.db.execute("delete from notifications where " + where, *args)

def function_clear_all(context):
	clear_where("1=1", [])

# clear/app and clear/object act on the CALLING app's own notifications only:
# the app comes from context (stamped by core), never from an argument, so one
# app cannot clear another's rows. Callers pass just the object.
def function_clear_app(context):
	app = context.get("app", "")
	if not app:
		return False
	clear_where("app = ?", [app])
	return True

def function_clear_object(context, object=""):
	app = context.get("app", "")
	if not app:
		return False
	clear_where("app = ? and object = ?", [app, object])
	mochi.websocket.write("notifications", {"type": "clear_object", "app": app, "object": object})
	return True

def function_list(context):
	return mochi.db.rows("select * from notifications order by created")

def function_read(context, id):
	now = mochi.time.now()
	# Look up the row's app/topic/object so subscribers (notably the Android
	# client) can reconstruct the system-notification tag "<app>-<topic>-<object>"
	# and cancel the matching tray entry.
	row = mochi.db.row("select app, topic, object from notifications where id = ?", id)
	if row:
		mochi.db.execute("update notifications set read = ? where id = ?", now, id)
	event = {"type": "read", "id": id}
	if row:
		event["app"] = row["app"]
		event["topic"] = row["topic"]
		event["object"] = row["object"]
	mochi.websocket.write("notifications", event)

def function_read_all(context):
	now = mochi.time.now()
	mochi.db.execute("update notifications set read = ? where read = 0", now)
	mochi.websocket.write("notifications", {"type": "read_all"})

def badge_count():
	row = mochi.db.row("select count(*) as count, coalesce(sum(count), 0) as total from notifications where read = 0")
	return {"count": row["count"] if row else 0, "total": row["total"] if row else 0}

def action_list(a):
	function_expire({})
	rows = function_list({})
	counts = badge_count()
	return {
		"data": rows,
		"count": counts["count"],
		"total": counts["total"]
	}

def action_count(a):
	function_expire({})
	return {"data": badge_count()}

def action_read(a):
	# Notification ids reach ~310 bytes: event-keyed rows are app id (~52) +
	# ":" + event id (capped at 256), and pre-namespacing rows carry raw
	# structured event ids over 100 bytes. A 64-byte cap rejected those.
	id = a.input("id", "").strip()
	if not id or len(id) > 512:
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

	feed_name = mochi.app.label("app.name")
	feed_token = a.input("token", "").strip()
	feed = None
	if len(feed_token) > 512:
		# Cannot match any stored token; skip the lookup.
		return a.error.label(404, "errors.feed_not_found")
	if feed_token:
		# The token identifies the feed and is the gate: an unknown token was
		# revoked with its feed, and a disabled feed's token stays revoked
		# until the feed is re-enabled. (A token invalid at the core layer
		# never reaches here - that's a 401 with no user.)
		feed = mochi.db.row("select id, name, enabled from rss where token = ?", feed_token)
		if not feed or not feed["enabled"]:
			return a.error.label(404, "errors.feed_not_found")
		feed_name = feed["name"]

	function_expire({})

	if feed:
		rows = mochi.db.rows("""
			select n.id, n.app, n.topic, n.title, n.content, n.link, n.count, n.created
			from notifications n
			join topics t on n.app = t.app and n.topic = t.topic and n.object = t.object
			join destinations d on d.category = t.category
			where d.type = 'rss' and d.target = ?
			order by n.created desc limit 100
		""", feed["id"])
	else:
		# Session access without a token is the user's own full bell view.
		rows = mochi.db.rows("""
			select id, app, topic, title, content, link, count, created
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
	a.print('<description>' + escape_xml(mochi.app.label("rss.description")) + '</description>\n')

	if rows:
		a.print('<lastBuildDate>' + mochi.time.local(rows[0]["created"], "rfc822") + '</lastBuildDate>\n')

	for row in rows:
		if row["app"] == "":
			app_name = server_name
		else:
			app_name = app_names.get(row["app"], row["app"].capitalize())
		# topic is a machine key ("invite/received"); headline only when title is
		# empty.
		title = app_name + ": " + (row["title"] if row["title"] else row["topic"])
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

# provider_valid reports whether `type` names a real account provider. Core
# rejects unknown types with a Starlark abort, which surfaces as an internal
# error, so the boundaries check first and answer a clean 400.
def provider_valid(type):
	if not type or len(type) > 64:
		return False
	for p in mochi.account.providers() or []:
		if p.get("type") == type:
			return True
	return False

# Connected accounts endpoints (thin wrappers around mochi.account.* API)

def action_accounts_providers(a):
	capability = a.input("capability")
	return {"data": mochi.account.providers(capability)}

def action_accounts_list(a):
	capability = a.input("capability")
	return {"data": mochi.account.list(capability)}

def action_accounts_get(a):
	# Account ids are mochi.uid() text since the integer-id re-keying; only
	# pre-migration rows kept digit ids, so an isdigit() check here (and in
	# update/remove/verify below) rejected every account created since.
	id = a.input("id", "").strip()
	if not id or len(id) > 64:
		a.error.label(400, "errors.invalid_id")
		return
	result = mochi.account.get(id)
	return {"data": result}

def action_accounts_add(a):
	type = a.input("type")
	if not type:
		a.error.label(400, "errors.type_is_required")
		return
	if not provider_valid(type):
		return a.error.label(400, "errors.invalid_type")

	fields = {}
	for key in ["label", "address", "token", "api_key", "url", "endpoint", "auth", "p256dh", "secret", "topic", "server"]:
		val = a.input(key)
		if val:
			if len(val) > 4096:
				a.error.label(400, "errors.value_too_long", maximum=4096)
				return
			fields[key] = val

	add_to_existing = a.input("add_to_existing", "1")
	add_to_existing = add_to_existing == "1" or add_to_existing == "true"

	result = mochi.account.add(type, **fields)

	if result and result.get("id"):
		account_id = result["id"]
		mochi.account.update(account_id, enabled=add_to_existing)
		# If flagged, add as destination to every existing category (except "0")
		if add_to_existing:
			add_destination_to_categories("account", str(account_id))

	return {"data": result}

def action_accounts_update(a):
	id = a.input("id", "").strip()
	if not id or len(id) > 64:
		a.error.label(400, "errors.invalid_id")
		return

	fields = {}
	label = a.input("label")
	if label != None:
		if len(label) > 4096:
			a.error.label(400, "errors.value_too_long", maximum=4096)
			return
		fields["label"] = label

	result = mochi.account.update(id, **fields)
	return {"data": result}

def action_accounts_remove(a):
	id = a.input("id", "").strip()
	if not id or len(id) > 64:
		a.error.label(400, "errors.invalid_id")
		return

	# Also remove from all categories' destinations and drop any queued
	# push rows - otherwise unscoped drains keep serving the dead account's
	# payloads until the 7-day TTL.
	row_remove("destinations", "type = 'account' and target = ?", [id])
	mochi.db.execute("delete from push_pending where account = ?", id)
	result = mochi.account.remove(id)
	return {"data": result}

def action_accounts_verify(a):
	id = a.input("id", "").strip()
	if not id or len(id) > 64:
		a.error.label(400, "errors.invalid_id")
		return

	code = a.input("code", "").strip()
	if not code or len(code) > 256:
		a.error.label(400, "errors.invalid_code")
		return
	result = mochi.account.verify(id, code)
	return {"data": result}

def action_accounts_vapid(a):
	key = mochi.webpush.key()
	if not key:
		return a.error.label(503, "errors.push_notifications_not_available")
	return {"data": {"key": key}}

def add_destination_to_categories(type, target):
	# Add this destination to every category except "0" (No notifications)
	cats = mochi.db.rows("select id from categories where id != '0'")
	for c in cats or []:
		row_merge("destinations", {"category": c["id"], "type": type, "target": target})

# function_destinations_add(context, type, target) -> bool: wire a (type,
# target) destination into every user category. Called by settings after adding
# an account.
def function_destinations_add(context, type="", target=""):
	if not type or not target:
		return False
	add_destination_to_categories(type, str(target))
	return True

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

	add_to_existing = a.input("add_to_existing", "1")
	add_to_existing = add_to_existing == "1" or add_to_existing == "true"

	id = mochi.uid()
	# Bound to the feed action. Notifications has no per-entity feed route -
	# the feed is selected by the token itself - so the binding carries no
	# entity, but it still stops the URL reaching the app's other actions.
	token = mochi.token.create("rss:" + id, ["rss"], 0, "-/rss", "")
	if not token:
		return a.error.label(500, "errors.failed_to_create_token")
	now = mochi.time.now()

	enabled = 1 if add_to_existing else 0
	mochi.db.execute("insert into rss (id, name, token, created, enabled) values (?, ?, ?, ?, ?)", id, name, token, now, enabled)

	if add_to_existing:
		add_destination_to_categories("rss", id)

	return {"data": {"id": id, "name": name, "token": token, "created": now, "enabled": enabled}}

def action_rss_delete(a):
	id = a.input("id", "").strip()
	if not id or len(id) > 64:
		return a.error.label(400, "errors.invalid_id")

	row = mochi.db.row("select token from rss where id = ?", id)
	if not row:
		return a.error.label(404, "errors.feed_not_found")

	# Revoke the RSS token by its stored string (exact, no name scan), so the
	# feed's ?token= URL stops working when the feed is removed.
	if row["token"]:
		mochi.token.delete(row["token"])

	row_remove("destinations", "type = 'rss' and target = ?", [id])
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
		# Accept both boolean forms, matching add_to_existing in rss/create;
		# parsing only "1" made enabled=true silently disable the feed.
		enabled_val = 1 if enabled == "1" or enabled == "true" else 0
		mochi.db.execute("update rss set enabled = ? where id = ?", enabled_val, id)

	return {"data": {}}

# Topic service functions

def function_send(context, topic, object="", title="", body="", url="", label="", name="", sender="", count=None, event_id=""):
	"""Send a notification from the calling app. Topics are keyed (app, topic, object),
	created on first send with the default category; label and name refresh on every send.
	count=None increments the unread count, an integer stores a state value; event_id keys
	a retried send to the same row. The empty app id is accepted only with context["_server"]."""
	app = context.get("app", "")
	if not app and not context.get("_server", False):
		return 0
	if not title or not body:
		return 0

	# Identity keys are rejected over-length (truncation could merge two topics);
	# display fields are truncated and delivered.
	if len(topic) > 128 or len(object) > 256 or len(event_id) > 256:
		return 0
	title = title[:256]
	body = body[:2048]
	label = label[:256]
	name = name[:256]
	sender = sender[:256]
	# A truncated URL is broken anyway; degrade to none.
	if len(url) > 2048:
		url = ""
	# Only a local path or mochi: URI may become a click target: a sender's scheme
	# or "//host" would leave the origin. Tab, newline, CR and backslash are
	# rejected anywhere - URL parsers strip or remap them, so "/\evil" still
	# changes authority.
	if url and ("\\" in url or "\t" in url or "\n" in url or "\r" in url):
		url = ""
	if url and not url.startswith("mochi:") and (not url.startswith("/") or url.startswith("//")):
		url = ""
	if count != None:
		# min/max abort the handler on a non-numeric; treat an unusable count as
		# absent.
		if type(count) not in ["int", "float"]:
			count = None
		else:
			count = min(max(int(count), 0), 999999)

	ensure_commit_hook_registered()

	row = mochi.db.row(
		"select label, name, category from topics where app = ? and topic = ? and object = ?",
		app, topic, object
	)
	if not row:
		default = mochi.db.row('select id from categories where "default" = 1')
		cat_val = default["id"] if default else None
		row_merge("topics", {"app": app, "topic": topic, "object": object, "label": label, "name": name, "category": cat_val, "created": mochi.time.now()})
		category = cat_val
	else:
		category = row["category"]
		# Refresh stored label/name if the caller passed one and it differs
		# (handles language switches, page renames, etc.).
		if label and label != row["label"]:
			row_set("topics", "app = ? and topic = ? and object = ?", [app, topic, object], {"label": label})
		if name and name != row["name"]:
			row_set("topics", "app = ? and topic = ? and object = ?", [app, topic, object], {"name": name})

	# "0" = No notifications: drop
	if category == "0":
		return 0

	now = mochi.time.now()
	content = title + ": " + body

	# Roll up onto the existing (app, topic, object) row so the id stays stable;
	# otherwise insert keyed by event_id when supplied.
	existing_notif = mochi.db.row(
		"select id, read, last_event from notifications where app = ? and topic = ? and object = ?",
		app, topic, object
	)
	if existing_notif:
		notif_id = existing_notif["id"]
		kind = "update"
		if count != None:
			mochi.db.execute(
				"update notifications set title=?, body=?, content=?, link=?, sender=?, created=?, read=0, count=?, fixed=1 where id=?",
				title, body, content, url, sender, now, count, notif_id
			)
		elif event_id and existing_notif["last_event"] == (app + ":" + event_id):
			# Already counted this event. A replay must still refresh the
			# content - the sender may be repairing it - but must not advance
			# the unread count again.
			mochi.db.execute(
				"update notifications set title=?, body=?, content=?, link=?, sender=?, created=? where id=?",
				title, body, content, url, sender, now, notif_id
			)
		else:
			mochi.db.execute(
				"update notifications set title=?, body=?, content=?, link=?, sender=?, created=?, read=0, count=case when read != 0 then 1 else count + 1 end, fixed=0, last_event=? where id=?",
				title, body, content, url, sender, now, (app + ":" + event_id) if event_id else "", notif_id
			)
	else:
		# Key the row by the caller's event id, namespaced by the sending app
		# so two apps notifying about the same source row cannot collide.
		notif_id = (app + ":" + event_id) if event_id else mochi.uid()
		kind = "insert"
		mochi.db.execute(
			"insert or ignore into notifications (id, app, topic, object, title, body, content, link, sender, count, created, read, fixed) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)",
			notif_id, app, topic, object, title, body, content, url, sender,
			count if count != None else 1, now, 1 if count != None else 0
		)
		# The insert is ignored when the id already keys another row (the
		# same app reusing an event id under a different topic or object).
		# Firing the hook for that id would redeliver the other row and this
		# notification would be silently lost - fall back to a fresh uid.
		if not mochi.db.exists("select 1 from notifications where id = ? and topic = ? and object = ?", notif_id, topic, object):
			notif_id = mochi.uid()
			mochi.db.execute(
				"insert into notifications (id, app, topic, object, title, body, content, link, sender, count, created, read, fixed) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)",
				notif_id, app, topic, object, title, body, content, url, sender,
				count if count != None else 1, now, 1 if count != None else 0
			)

	# Fire the commit hook for the write: it emits the websocket event and,
	# for unread rows, fans out external deliveries (account push, email,
	# pushbullet, ntfy) through the topic's category destinations.
	mochi.db.commit.fire("notifications", kind, notif_id)
	return 1

# Commit hook for the notifications table: websocket emission plus external
# delivery fan-out for unread rows.
def notifications_commit_hook(table, kind, row_uid):
	if table != "notifications":
		return
	if kind not in ("insert", "update"):
		return
	if not row_uid:
		return
	row = mochi.db.row("select * from notifications where id = ?", row_uid)
	if not row:
		return

	# Emit to any connected browser tabs subscribed to "notifications".
	mochi.websocket.write("notifications", {
		"type": "new",
		"id": row["id"],
		"app": row["app"],
		"topic": row["topic"],
		"object": row["object"],
		"content": row["content"],
		"link": row["link"],
		"count": row["count"],
		"created": row["created"],
		"read": row["read"],
	})

	# Skip external delivery for read rows (the row was marked read; no
	# new event fired).
	if row["read"]:
		return

	topic_row = mochi.db.row(
		"select category from topics where app = ? and topic = ? and object = ?",
		row["app"], row["topic"], row["object"]
	)
	if not topic_row:
		return
	category = topic_row["category"]
	# "0" = "No notifications", NULL = no default category (web-only).
	if category == "0" or category == None:
		return

	dests = mochi.db.rows(
		"select type, target from destinations where category = ?",
		category
	)
	for dest in dests or []:
		if dest["type"] == "account":
			account_id = dest["target"]
			push_queue_if_unifiedpush(account_id, row["app"], row["topic"], row["object"], row["title"], row["body"], row["link"], row["id"])
			mochi.account.notify(
				account=account_id,
				app=row["app"],
				category=row["topic"],
				object=row["object"],
				title=row["title"],
				body=row["body"],
				link=row["link"],
				id=row["id"]
			)
		# web destinations are handled by the websocket emission above;
		# rss destinations are queried on demand, no active delivery.

# Registered lazily from function_send: mochi.db.commit.hook needs the request's
# user/app context, which module load lacks. Re-registering is a cheap
# assignment.
def ensure_commit_hook_registered():
	mochi.db.commit.hook("notifications_commit_hook")

def function_topics(context, object=None):
	"""List topic rows belonging to the calling app."""
	app = context.get("app", "")
	if not app:
		return []
	if object != None:
		return mochi.db.rows("select * from topics where app = ? and object = ?", app, object) or []
	return mochi.db.rows("select * from topics where app = ?", app) or []

def function_topic_remove(context, topic="", object=""):
	"""Remove a topic row belonging to the calling app."""
	app = context.get("app", "")
	if not app:
		return False
	row_remove("topics", "app = ? and topic = ? and object = ?", [app, topic, object])
	return True

# Label to render for a category: the two seeds store English literals, so they
# are translated at read time while unrenamed. Consumers show display and edit
# label.
def category_display(id, label):
	if id == "0" and label == "No notifications":
		return mochi.app.label("category.none")
	if id == "1" and label == "Normal":
		return mochi.app.label("category.normal")
	return label

# Permission-gated function for apps to list categories (for pickers shown in app UI).
# Kept narrow — only labels and ids, no destinations.
def function_categories(context):
	rows = mochi.db.rows('select id, label, "default" from categories order by id') or []
	for row in rows:
		row["display"] = category_display(row["id"], row["label"])
	return rows

# Category CRUD — used by the settings page via the service proxy; gated by
# notifications/write in app.json.

def function_category_list(context):
	cats = mochi.db.rows('select id, label, "default", created from categories order by id') or []
	result = []
	for c in cats:
		dests = mochi.db.rows("select type, target from destinations where category = ?", c["id"]) or []
		c["destinations"] = dests
		c["display"] = category_display(c["id"], c["label"])
		result.append(c)
	return result

def function_category_create(context, label="", destinations=None, default=None):
	# 100 matches the RSS feed-name cap; mochi.text.valid alone allows 1MB.
	if not label or len(label) > 100 or not mochi.text.valid(label, "text"):
		return None
	now = mochi.time.now()
	cid = mochi.uid()
	row_merge("categories", {"id": cid, "label": label, "default": 0, "created": now})
	apply_destinations(cid, destinations)
	if default:
		set_default(cid)
	return cid

def set_default(id):
	# Enforce exactly-one-default invariant. The "0" (No notifications)
	# sentinel category can't be the default.
	if not id or id == "0":
		return
	row_set("categories", "1=1", [], {"default": 0})
	row_set("categories", "id = ?", [id], {"default": 1})

def function_category_update(context, id=None, label=None, destinations=None, default=None):
	if not id:
		return False
	if not mochi.db.exists("select 1 from categories where id = ?", id):
		return False
	if label != None:
		if len(label) > 100 or not mochi.text.valid(label, "text"):
			return False
		row_set("categories", "id = ?", [id], {"label": label})
	if default != None and id != "0":
		# Only allow setting default on (can't unset without picking another).
		if default:
			set_default(id)
	if destinations != None and id != "0":
		apply_destinations(id, destinations)
	return True

def function_category_delete(context, id=None, reassign_to=None):
	if not id or id == "0":
		return False
	if not mochi.db.exists("select 1 from categories where id = ?", id):
		return False
	if reassign_to == None:
		return False
	if not mochi.db.exists("select 1 from categories where id = ?", reassign_to):
		return False
	if reassign_to == id:
		return False
	# If we're deleting the default, promote the reassign target to be the new
	# default (can't leave the system without a default).
	was_default = mochi.db.exists('select 1 from categories where id = ? and "default" = 1', id)
	row_set("topics", "category = ?", [id], {"category": reassign_to})
	row_remove("destinations", "category = ?", [id])
	row_remove("categories", "id = ?", [id])
	if was_default:
		set_default(reassign_to)
	return True

def function_category_test(context, id=None):
	"""Send a test notification through the category's destinations. A bell entry is
	always written, even without a web destination, so the click gets visible feedback."""
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
	# Written directly rather than through function_send: the test bypasses topic
	# routing.
	now = mochi.time.now()
	existing_notif = mochi.db.row(
		"select id from notifications where app = 'notifications' and topic = 'test' and object = ?",
		str(id)
	)
	notif_id = existing_notif["id"] if existing_notif else mochi.uid()
	content = title + ": " + body_web
	# State-style: fixed=1 so the stored count of 1 is shown as-is.
	row_merge("notifications", {
		"id": notif_id, "app": "notifications", "topic": "test", "object": str(id),
		"title": title, "body": body_web, "content": content,
		"link": "/settings/user/notifications", "sender": "",
		"count": 1, "created": now, "read": 0, "fixed": 1,
	})
	mochi.websocket.write("notifications", {
		"type": "new",
		"id": notif_id,
		"app": "notifications",
		"topic": "test",
		"object": str(id),
		"content": content,
		"link": "/settings/user/notifications",
		"count": 1,
		"created": now,
		"read": 0,
	})
	for dest in dests:
		if dest["type"] == "web":
			web = True
			sent += 1
		elif dest["type"] == "account":
			account_id = dest["target"]
			account_label = account_display_label(account_id)
			if not account_label:
				continue  # stale destination row pointing at a deleted account
			body = mochi.app.label("notifications.body.test_via_account", account=account_label)
			push_queue_if_unifiedpush(account_id, "notifications", "test", "", title, body, "", notif_id)
			mochi.account.notify(
				account=account_id,
				app="notifications",
				category="test",
				object="",
				title=title,
				body=body,
				link="",
				id=notif_id
			)
			sent += 1
	return {"sent": sent, "web": web}

def account_display_label(account_id):
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

def apply_destinations(category_id, destinations):
	if destinations == None:
		return
	if category_id == "0":
		return
	row_remove("destinations", "category = ?", [category_id])
	for dest in destinations:
		# Service callers can pass arbitrary shapes; skip elements that are
		# not dicts, carry an unknown type, or an over-long target rather
		# than aborting or persisting junk (the HTTP actions reject upfront).
		if type(dest) != "dict":
			continue
		dest_type = dest.get("type", "")
		dest_target = str(dest.get("target", ""))
		if dest_type not in ("web", "account", "rss") or len(dest_target) > 64:
			continue
		row_merge("destinations", {"category": category_id, "type": dest_type, "target": dest_target})

# destinations_input decodes and shape-checks the client's destinations JSON
# parameter: a bounded list of dicts, or absent. Returns (valid, destinations);
# on invalid input the caller answers 400.
def destinations_input(a):
	raw = a.input("destinations", "").strip()
	if not raw:
		return True, None
	destinations = json.decode(raw, None)
	if type(destinations) != "list" or len(destinations) > 100:
		return False, None
	for dest in destinations:
		if type(dest) != "dict":
			return False, None
		if dest.get("type", "") not in ("web", "account", "rss"):
			return False, None
		if len(str(dest.get("target", ""))) > 64:
			return False, None
	return True, destinations

# Topic helpers — used by settings page and notification dropdown

def function_topic_list(context):
	"""List every topic row with app name resolved. The object's display name
	is the stored `name` (set by the calling app on send); for objects that
	are global entities we fall back to mochi.entity.name() so feeds/forums/
	projects keep working without each app having to supply a name."""
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
		if not row.get("name") and row["object"] and mochi.text.valid(row["object"], "entity"):
			row["name"] = mochi.entity.name(row["object"]) or ""
		result.append(row)
	return result

def function_topic_category_set(context, app="", topic="", object="", category=None):
	# app="" identifies server-originated topics (e.g. upgrade notifications),
	# which the user owns and must be able to recategorise like any other.
	if not mochi.db.exists(
		"select 1 from topics where app = ? and topic = ? and object = ?",
		app, topic, object
	):
		return False
	if category == None:
		row_set("topics", "app = ? and topic = ? and object = ?", [app, topic, object], {"category": None})
	else:
		if not mochi.db.exists("select 1 from categories where id = ?", category):
			return False
		row_set("topics", "app = ? and topic = ? and object = ?", [app, topic, object], {"category": category})
	return True

def function_topic_lookup(context, app="", topic="", object=""):
	"""Find the topic row matching (app, topic, object) for the per-notification picker.
	Returns the row with category, or None if no row exists yet. app="" matches
	server-originated topics (upgrade alerts etc.)."""
	return mochi.db.row(
		"select app, topic, object, label, name, category from topics where app = ? and topic = ? and object = ?",
		app, topic, object
	)

def function_topic_delete(context, app="", topic="", object=""):
	"""Delete any topic row by (app, topic, object). Used by the settings page.
	app="" matches server-originated topics."""
	if not mochi.db.exists(
		"select 1 from topics where app = ? and topic = ? and object = ?",
		app, topic, object
	):
		return False
	row_remove("topics", "app = ? and topic = ? and object = ?", [app, topic, object])
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
	valid, destinations = destinations_input(a)
	if not valid:
		return a.error.label(400, "errors.invalid_destinations")
	cid = function_category_create({}, label, destinations, default)
	if not cid:
		return a.error.label(400, "errors.invalid_category")
	return {"data": {"id": cid}}

def action_categories_update(a):
	id = a.input("id", "").strip()
	if not id or len(id) > 64:
		return a.error.label(400, "errors.invalid_id")
	label = a.input("label")
	default_raw = a.input("default")
	default = None
	if default_raw != None and default_raw != "":
		default = 1 if default_raw == "1" or default_raw == "true" else 0
	valid, destinations = destinations_input(a)
	if not valid:
		return a.error.label(400, "errors.invalid_destinations")
	ok = function_category_update({}, id, label, destinations, default)
	if not ok:
		return a.error.label(404, "errors.not_found")
	return {"data": {}}

def action_categories_delete(a):
	id = a.input("id", "").strip()
	reassign = a.input("reassign_to", "").strip()
	if not id or len(id) > 64:
		return a.error.label(400, "errors.invalid_id")
	if not reassign or len(reassign) > 64:
		return a.error.label(400, "errors.reassign_to_is_required")
	ok = function_category_delete({}, id, reassign)
	if not ok:
		return a.error.label(400, "errors.could_not_delete")
	return {"data": {}}

def action_categories_test(a):
	id = a.input("id", "").strip()
	if not id or len(id) > 64:
		return a.error.label(400, "errors.invalid_id")
	return {"data": function_category_test({}, id)}

def action_topics_list(a):
	return {"data": function_topic_list({})}

def action_topics_set_category(a):
	# An empty category clears the topic's category; anything over-long cannot
	# name a real category and is rejected rather than treated as a clear.
	app = a.input("app", "").strip()
	topic = a.input("topic", "").strip()
	object = a.input("object", "").strip()
	category = a.input("category", "").strip()
	if category == "":
		category = None
	elif len(category) > 64:
		return a.error.label(404, "errors.not_found")
	ok = function_topic_category_set({}, app, topic, object, category)
	if not ok:
		return a.error.label(404, "errors.not_found")
	return {"data": {}}

def action_topics_lookup(a):
	"""Find the topic row matching (app, topic, object) for the dropdown picker."""
	app = a.input("app", "").strip()
	topic = a.input("topic", "").strip()
	object = a.input("object", "").strip()
	row = function_topic_lookup({}, app, topic, object)
	return {"data": row}

def action_topics_delete(a):
	app = a.input("app", "").strip()
	topic = a.input("topic", "").strip()
	object = a.input("object", "").strip()
	if not function_topic_delete({}, app, topic, object):
		return a.error.label(404, "errors.topic_not_found")
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
	if not provider_valid(type):
		return None
	# Bound each field like the HTTP action_accounts_add path (4096/field). This
	# service call is the other entry point to the same account insert (the menu
	# shell reaches it via mochi.service.call), so it must enforce the same limit
	# rather than store unbounded values.
	for value in fields.values():
		if len(str(value)) > 4096:
			return None
	result = mochi.account.add(type, **fields)
	if result and result.get("id"):
		account_id = result["id"]
		mochi.account.update(account_id, enabled=True)
		add_destination_to_categories("account", str(account_id))
	return result

def function_accounts_remove(context, id=0):
	if not id:
		return None
	row_remove("destinations", "type = 'account' and target = ?", [str(id)])
	mochi.db.execute("delete from push_pending where account = ?", str(id))
	return mochi.account.remove(id)

# UnifiedPush registration. endpoint="" is the local distributor: the server
# allocates a path the app appends to its server URL. A set endpoint is a
# third-party distributor (ntfy etc), stored opaque and POSTed to per RFC 8030
# at delivery.
def function_push_register(context, label="", auth="", p256dh="", endpoint=""):
	if not auth or not p256dh:
		return None
	# Bound like the accounts paths: over-length registration input is a
	# caller bug, refused outright (real auth is ~22 chars, p256dh ~88).
	if len(auth) > 512 or len(p256dh) > 512 or len(endpoint) > 2048 or len(label) > 256:
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
		path = "/menu/-/push/inbound/%s" % account_id
		mochi.account.update(account_id, endpoint=path)
		result["endpoint"] = path

	mochi.account.update(account_id, enabled=True)
	add_destination_to_categories("account", str(account_id))
	return result

# Stores an FCM device token keyed by Firebase Installations ID: core upserts,
# so a token refresh updates the row in place and a second device gets its own
# row.
def function_push_register_fcm(context, token="", install_id="", device=""):
	if not token or not install_id:
		return None
	if len(token) > 512 or len(install_id) > 256 or len(device) > 256:
		return None
	kwargs = {"token": token, "install_id": install_id}
	if device:
		kwargs["label"] = device
	result = mochi.account.add("fcm", **kwargs)
	if not result or not result.get("id"):
		return result
	account_id = result["id"]
	mochi.account.update(account_id, enabled=True)
	add_destination_to_categories("account", str(account_id))
	return result

# Tells the client its push transport: {"transport": "fcm", "firebase_config":
# {...}} when the admin pasted Firebase config (google-services.json verbatim or
# a flat {project_id, app_id, api_key, messaging_sender_id}), else {"transport":
# "unifiedpush"}.
def function_push_setup(context):
	config_raw = mochi.setting.get("fcm.firebase_config")
	if not config_raw:
		return {"transport": "unifiedpush"}
	config = json.decode(config_raw)
	if type(config) != "dict":
		return {"transport": "unifiedpush"}
	extracted = extract_firebase_config(config)
	if not extracted:
		return {"transport": "unifiedpush"}
	return {"transport": "fcm", "firebase_config": extracted}

def extract_firebase_config(raw):
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
def function_push_inbound(context, account_id="", payload=""):
	if not account_id:
		return {"ok": False, "error": "missing account_id"}
	# TODO: forward via mochi.websocket.write once the Go side exposes a
	# binary-safe write (current API is JSON text only).
	return {"ok": False, "error": "inbound endpoint not yet implemented"}

# Queues a durable backstop row for local-distributor unifiedpush accounts, for
# when the device's WebSocket is not subscribed; the phone drains and acks it
# via push/drain and push/ack. Foreign distributors and other account types
# handle their own retry.
def push_queue_if_unifiedpush(account_id, app, topic, object, title, body, url, notif_id):
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
	# to live ones (same RFC 8030 body fields). `id` lets the phone call -/read
	# on tap so the matching web row is cleared.
	payload = json.encode({
		"title": title,
		"body": body,
		"link": url,
		"tag": app + "-" + topic + "-" + object,
		"id": notif_id,
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

# Returns pending unifiedpush rows and sweeps rows older than 7 days. Read-only:
# the phone acks via function_push_ack after posting, so a crash mid-drain
# re-drains. subscription is client-asserted - a courtesy filter between one
# user's devices, not a boundary.
def function_push_drain(context, subscription=""):
	now = mochi.time.now()
	# Opportunistic TTL sweep: drop rows older than 7 days, regardless of
	# account or subscriber state. Pattern mirrors the unifiedpush account
	# TTL sweep in api_account_notify (core/server/accounts.go).
	mochi.db.execute(
		"delete from push_pending where created < ?", now - 7 * 86400
	)
	if subscription:
		rows = mochi.db.rows(
			"select account, event_id, subscription, payload, created from push_pending where subscription = ? order by created",
			subscription
		) or []
	else:
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

# Deletes the named rows; acking a missing row is a no-op. subscription bounds
# the delete to one device's rows and is client-asserted - a courtesy filter,
# not a security boundary.
def function_push_ack(context, account_event_ids=None, subscription=""):
	if not account_event_ids:
		return {"acked": 0}
	acked = 0
	for ae in account_event_ids:
		if type(ae) != "dict":
			continue
		account = ae.get("account", "")
		event_id = ae.get("event_id", "")
		if not account or not event_id:
			continue
		if subscription:
			mochi.db.execute(
				"delete from push_pending where account = ? and event_id = ? and subscription = ?",
				account, event_id, subscription
			)
		else:
			mochi.db.execute(
				"delete from push_pending where account = ? and event_id = ?",
				account, event_id
			)
		acked += 1
	return {"acked": acked}

# Client-facing action wrappers.

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
	if not provider_valid(type):
		return a.error.label(400, "errors.invalid_type")
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
	if not id or len(id) > 64:
		return a.error.label(400, "errors.invalid_id")
	result = function_accounts_remove(None, id=id)
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
	"""Register the client's FCM device token, keyed by Firebase Installations ID."""
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
	"""Return queued unifiedpush events. Read-only: the phone posts push/ack with the
	(account, event_id) pairs it delivered. subscription=<id> limits to one device."""
	subscription = a.input("subscription", "").strip()
	return {"data": function_push_drain(None, subscription=subscription) or []}

def action_push_ack(a):
	"""Delete acknowledged rows from the pending queue. Body: events=<JSON
	array of {account, event_id}>. Idempotent — acking a row that no
	longer exists is a no-op (TTL'd, manually cleared, or never queued
	because of a live race)."""
	events_raw = a.input("events", "")
	if not events_raw:
		return {"data": {"acked": 0}}
	events = json.decode(events_raw, None)
	if type(events) != "list" or len(events) > 1000:
		return a.error.label(400, "errors.invalid_subscription")
	subscription = a.input("subscription", "").strip()
	return {"data": function_push_ack(None, account_event_ids=events, subscription=subscription) or {"acked": 0}}
