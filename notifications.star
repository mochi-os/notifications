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
	if version == 5:
		# push_pending -> queue, and its event_id column -> event: both are
		# glued/abbreviated names on storage the drain envelope mirrors. The
		# table cannot be called `pending` - core creates a `pending` table of
		# its own in every app database (the broadcast pending buffer).
		if mochi.db.table("push_pending"):
			mochi.db.execute("drop index if exists push_pending_created")
			mochi.db.execute("alter table push_pending rename to queue")
		columns = []
		for column in mochi.db.table("queue"):
			columns.append(column["name"])
		if "event_id" in columns:
			mochi.db.execute("alter table queue rename column event_id to event")
		mochi.db.execute("create index if not exists queue_created on queue(account, created)")
		columns = []
		for column in mochi.db.table("notifications"):
			columns.append(column["name"])
		if "last_event" in columns:
			mochi.db.execute("alter table notifications rename column last_event to event")
		# Expiry used to run as a delete on every list/count/rss request; the
		# stamp lets it run at most hourly.
		maintenance_schema_create()
		# Backfill the display name every send has supplied since topics grew a
		# name column, so the read path no longer resolves entities one row at
		# a time.
		for row in mochi.db.rows("select app, topic, object from topics where name = '' and object != ''") or []:
			if not mochi.text.valid(row["object"], "entity"):
				continue
			name = mochi.entity.name(row["object"]) or ""
			if name:
				mochi.db.execute(
					"update topics set name=? where app=? and topic=? and object=?",
					name, row["app"], row["topic"], row["object"]
				)
	if version == 4:
		# Rebuild push_pending.account as text: under integer affinity an all-digit
		# uid was stored as a number, losing leading zeros, so the text uid the select
		# and delete paths pass never matched.
		# The table this reads was created by the schema of the day; version 5
		# renames it to `queue`, so nothing later builds it. Declare it here so
		# the migration is self-contained - on a database that reaches this step
		# the table always exists and the create is a no-op.
		mochi.db.execute("""create table if not exists push_pending (
			account text not null,
			event_id text not null,
			subscription text not null,
			payload text not null,
			created integer not null,
			primary key (account, event_id)
		)""")
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
		event text not null default '',
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

	mochi.db.execute("""create table if not exists queue (
		account text not null,
		event text not null,
		subscription text not null,
		payload text not null,
		created integer not null,
		primary key (account, event)
	)""")
	mochi.db.execute("create index if not exists queue_created on queue(account, created)")

	maintenance_schema_create()

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

# Housekeeping stamps. One row per job, so a sweep can be rate-limited
# without running its delete on every read request.
def maintenance_schema_create():
	mochi.db.execute("""create table if not exists maintenance (
		name text not null primary key,
		time integer not null default 0
	)""")

EXPIRE_INTERVAL = 3600

# expire_due claims the expiry slot for this request, at most once an hour.
# The stamp is written before the delete: a concurrent request must not run
# the same sweep, and losing one hour's expiry to a failed delete is cheaper
# than every list, count and RSS request writing to the notifications table.
def expire_due():
	now = mochi.time.now()
	row = mochi.db.row("select time from maintenance where name = 'expire'")
	if row and now - row["time"] < EXPIRE_INTERVAL:
		return False
	mochi.db.execute(
		"insert into maintenance (name, time) values ('expire', ?) on conflict(name) do update set time = excluded.time",
		now
	)
	return True

def expire():
	if not expire_due():
		return
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

# The join and condition restricting notifications n to the rows a surface
# sees, with the condition's arguments. A surface is where a notification is
# visible - "web" is the shared browser bell, a device is one phone's own list
# - as distinct from the push targets it is delivered to. A registered device
# is its own surface whatever else the request asks for; a caller with neither
# sees every row. The category carries the destinations, so a topic with no
# category, or a row with no topic, shows on every surface.
def surface_filter(surface, device=""):
	if device:
		type, target = "device", device
	elif surface == "web":
		type, target = "web", ""
	else:
		return "", "", []
	join = " left join topics t on t.app = n.app and t.topic = n.topic and t.object = n.object"
	condition = "(t.category is null or exists (select 1 from destinations d where d.category = t.category and d.type = ? and d.target = ?))"
	return join, condition, [type, target]

def function_list(context, surface="", device=""):
	join, condition, args = surface_filter(surface, device)
	where = " where " + condition if condition else ""
	return mochi.db.rows("select n.* from notifications n" + join + where + " order by n.created", *args)

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

def badge_count(surface="", device=""):
	join, condition, args = surface_filter(surface, device)
	where = " where n.read = 0" + (" and " + condition if condition else "")
	row = mochi.db.row("select count(*) as count, coalesce(sum(n.count), 0) as total from notifications n" + join + where, *args)
	return {"count": row["count"] if row else 0, "total": row["total"] if row else 0}

# The caller asserts its surface: the browser bell sends surface=web, the
# Android app its Device header. A client that sends neither sees every row.
def action_list(a):
	expire()
	surface = a.input("surface", "")
	device = device_header(a)
	rows = function_list({}, surface, device)
	counts = badge_count(surface, device)
	return {
		"data": rows,
		"count": counts["count"],
		"total": counts["total"]
	}

def action_count(a):
	expire()
	return {"data": badge_count(a.input("surface", ""), device_header(a))}

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

	expire()

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
	names = {}
	for entry in all_apps:
		names[entry["id"]] = entry["name"]
		for path in entry.get("paths", []):
			names[path] = entry["name"]
	server_name = mochi.app.label("notifications.app.server")

	a.header("Content-Type", "application/rss+xml; charset=utf-8")

	a.print('<?xml version="1.0" encoding="UTF-8"?>\n')
	a.print('<rss version="2.0">\n')
	a.print('<channel>\n')
	origin = a.origin
	a.print('<title>' + escape_xml(feed_name) + '</title>\n')
	a.print('<link>' + escape_xml(origin + '/notifications') + '</link>\n')
	a.print('<description>' + escape_xml(mochi.app.label("rss.description")) + '</description>\n')

	if rows:
		a.print('<lastBuildDate>' + mochi.time.local(rows[0]["created"], "rfc822") + '</lastBuildDate>\n')

	for row in rows:
		if row["app"] == "":
			label = server_name
		else:
			label = names.get(row["app"], row["app"].capitalize())
		# topic is a machine key ("invite/received"); headline only when title is
		# empty.
		title = label + ": " + (row["title"] if row["title"] else row["topic"])
		if row["count"] > 1:
			title = title + " (" + str(row["count"]) + ")"

		# A stored link is a site path ("/feeds/abc"); anything else - a
		# mochi: link, or an absolute URL an app supplied - is left alone.
		link = row["link"] if row["link"] else "/notifications"
		if link.startswith("/"):
			link = origin + link

		a.print('<item>\n')
		a.print('<title>' + escape_xml(title) + '</title>\n')
		a.print('<link>' + escape_xml(link) + '</link>\n')
		a.print('<description>' + escape_xml(row["content"]) + '</description>\n')
		a.print('<pubDate>' + mochi.time.local(row["created"], "rfc822") + '</pubDate>\n')
		a.print('<guid isPermaLink="false">' + escape_xml(row["id"]) + '</guid>\n')
		a.print('</item>\n')

	a.print('</channel>\n')
	a.print('</rss>')

# provider_get returns the account provider `type` names, or None. Core rejects
# an unknown type with a Starlark abort, which surfaces as an internal error, so
# the boundary checks first and refuses cleanly.
def provider_get(type):
	if not type or len(type) > 64:
		return None
	for p in mochi.account.providers() or []:
		if p.get("type") == type:
			return p
	return None

# Connected account removal. The rest of the connected-account surface -
# providers, list, get, add, update, verify, vapid - is the settings app's,
# which reaches mochi.account.* directly and proxies the notification parts
# through this app's service functions. This route stays because the Android
# client calls it directly to drop a dead push account.

def action_accounts_remove(a):
	# Account ids are mochi.uid() text since the integer-id re-keying; only
	# pre-migration rows kept digit ids, so an isdigit() check here rejected
	# every account created since.
	id = a.input("id", "").strip()
	if not id or len(id) > 64:
		a.error.label(400, "errors.invalid_id")
		return

	# Also remove from all categories' destinations and drop any queued
	# push rows - otherwise unscoped drains keep serving the dead account's
	# payloads until the 7-day TTL.
	row_remove("destinations", "type = 'account' and target = ?", [id])
	mochi.db.execute("delete from queue where account = ?", id)
	result = mochi.account.remove(id)
	return {"data": result}

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
	# Same bounds apply_destinations enforces: an unknown type is never
	# delivered, and an over-long target is not a real destination.
	if type not in DESTINATION_TYPES or len(str(target)) > 64:
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

	existing = a.input("existing", "1")
	existing = existing == "1" or existing == "true"

	id = mochi.uid()
	# Bound to the feed action. Notifications has no per-entity feed route -
	# the feed is selected by the token itself - so the binding carries no
	# entity, but it still stops the URL reaching the app's other actions.
	token = mochi.token.create("rss:" + id, ["rss"], 0, "-/rss", "")
	if not token:
		return a.error.label(500, "errors.failed_to_create_token")
	now = mochi.time.now()

	enabled = 1 if existing else 0
	mochi.db.execute("insert into rss (id, name, token, created, enabled) values (?, ?, ?, ?, ?)", id, name, token, now, enabled)

	if existing:
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
		# Accept both boolean forms, matching existing in rss/create;
		# parsing only "1" made enabled=true silently disable the feed.
		enabled_val = 1 if enabled == "1" or enabled == "true" else 0
		mochi.db.execute("update rss set enabled = ? where id = ?", enabled_val, id)

	return {"data": {}}

# Topic service functions

def function_send(context, topic, object="", title="", body="", url="", label="", name="", sender="", count=None, event=""):
	"""Send a notification from the calling app. Topics are keyed (app, topic, object),
	created on first send with the default category; label and name refresh on every send.
	count=None increments the unread count, an integer stores a state value; event keys
	a retried send to the same row. The empty app id is accepted only with context["_server"]."""
	app = context.get("app", "")
	if not app and not context.get("_server", False):
		return 0
	if not title or not body:
		return 0

	# topic, object and event come from the calling app, so a non-string one
	# would reach len() below and abort the send rather than be refused.
	if type(topic) != "string" or type(object) != "string" or type(event) != "string":
		return 0

	# Identity keys are rejected over-length (truncation could merge two topics);
	# display fields are truncated and delivered.
	if len(topic) > 128 or len(object) > 256 or len(event) > 256:
		return 0

	# Display fields are sliced and measured below, which aborts on a
	# non-string just as len() does above. a.input() answers None for a
	# missing field, so a calling app relaying one lands here.
	for value in (title, body, url, label, name, sender):
		if type(value) != "string":
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
	# otherwise insert keyed by event when supplied.
	existing_notif = mochi.db.row(
		"select id, read, event from notifications where app = ? and topic = ? and object = ?",
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
		elif event and existing_notif["event"] == (app + ":" + event):
			# Already counted this event. A replay must still refresh the
			# content - the sender may be repairing it - but must not advance
			# the unread count again, and must not re-deliver: core's email,
			# Pushbullet, ntfy and URL senders carry no event-level dedup, so
			# a second fire is a second message in the user's mailbox. "refresh"
			# reaches the hook's websocket write and stops before the fan-out.
			kind = "refresh"
			mochi.db.execute(
				"update notifications set title=?, body=?, content=?, link=?, sender=?, created=? where id=?",
				title, body, content, url, sender, now, notif_id
			)
		else:
			mochi.db.execute(
				"update notifications set title=?, body=?, content=?, link=?, sender=?, created=?, read=0, count=case when read != 0 then 1 else count + 1 end, fixed=0, event=? where id=?",
				title, body, content, url, sender, now, (app + ":" + event) if event else "", notif_id
			)
	else:
		# Key the row by the caller's event id, namespaced by the sending app
		# so two apps notifying about the same source row cannot collide.
		notif_id = (app + ":" + event) if event else mochi.uid()
		kind = "insert"
		mochi.db.execute(
			"insert or ignore into notifications (id, app, topic, object, title, body, content, link, sender, count, created, read, fixed, event) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)",
			notif_id, app, topic, object, title, body, content, url, sender,
			count if count != None else 1, now, 1 if count != None else 0,
			(app + ":" + event) if event else ""
		)
		# The insert is ignored when the id already keys another row (the
		# same app reusing an event id under a different topic or object).
		# Firing the hook for that id would redeliver the other row and this
		# notification would be silently lost - fall back to a fresh uid.
		if not mochi.db.exists("select 1 from notifications where id = ? and topic = ? and object = ?", notif_id, topic, object):
			notif_id = mochi.uid()
			mochi.db.execute(
				"insert into notifications (id, app, topic, object, title, body, content, link, sender, count, created, read, fixed, event) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)",
				notif_id, app, topic, object, title, body, content, url, sender,
				count if count != None else 1, now, 1 if count != None else 0,
				(app + ":" + event) if event else ""
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
	if kind not in ("insert", "update", "refresh"):
		return
	if not row_uid:
		return
	row = mochi.db.row("select * from notifications where id = ?", row_uid)
	if not row:
		return

	# Tell every subscribed client - browser tabs, the Android badge - to
	# refetch. Unconditional on purpose: each client's list is filtered by its
	# own surface on read (surface_filter), so a row hidden from the bell is
	# announced and then not returned.
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

	# A refresh carries no new event: the content changed, the count did not,
	# and every destination has already been told once.
	if kind == "refresh":
		return

	# Skip external delivery for read rows (the row was marked read; no
	# new event fired).
	if row["read"]:
		return

	# The category test delivers to accounts itself, one send per account so
	# it can name the account in the body and count each result; only the
	# websocket emission above is wanted from here.
	if row["app"] == "notifications" and row["topic"] == "test":
		return

	topic_row = mochi.db.row(
		"select category from topics where app = ? and topic = ? and object = ?",
		row["app"], row["topic"], row["object"]
	)
	if not topic_row:
		return
	category = topic_row["category"]
	# "0" = "No notifications", NULL = no default category: shown on every
	# surface, delivered nowhere.
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
		# Surfaces (web) and rss destinations need no delivery: both are
		# applied when the rows are read.

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
		# "" reaches here as a rename to nothing - mochi.text.valid's "text"
		# type caps length and admits the empty string. None means "leave
		# unchanged" and is handled by the branch above.
		if not label or len(label) > 100 or not mochi.text.valid(label, "text"):
			return False
		row_set("categories", "id = ?", [id], {"label": label})
	if default != None and id != "0":
		# Only allow setting default on (can't unset without picking another).
		if default:
			set_default(id)
	if destinations != None and id != "0":
		apply_destinations(id, destinations)
	return True

def function_category_delete(context, id=None, reassign=None):
	if not id or id == "0":
		return False
	if not mochi.db.exists("select 1 from categories where id = ?", id):
		return False
	if reassign == None:
		return False
	if not mochi.db.exists("select 1 from categories where id = ?", reassign):
		return False
	if reassign == id:
		return False
	# If we're deleting the default, promote the reassign target to be the new
	# default (can't leave the system without a default).
	was_default = mochi.db.exists('select 1 from categories where id = ? and "default" = 1', id)
	row_set("topics", "category = ?", [id], {"category": reassign})
	row_remove("destinations", "category = ?", [id])
	row_remove("categories", "id = ?", [id])
	if was_default:
		set_default(reassign)
	return True

def function_category_test(context, id=None):
	"""Send a test notification through the category's destinations, routed the
	way a real notification is: a topics row binds the test tuple to the
	category, so each in-app surface's filter and the category's RSS feeds
	decide visibility themselves. The count reports destinations actually
	reached, with push failures counted separately."""
	if not id:
		return {"sent": 0, "failed": 0, "total": 0, "web": False}
	cat = mochi.db.row("select label from categories where id = ?", id)
	if not cat:
		return {"sent": 0, "failed": 0, "total": 0, "web": False}
	dests = mochi.db.rows("select type, target from destinations where category = ?", id) or []
	title = mochi.app.label("notifications.body.test")
	body = mochi.app.label("notifications.body.test_category", name=cat["label"])
	now = mochi.time.now()

	web = False
	surfaces = 0
	feeds = 0
	for dest in dests:
		if dest["type"] == "web":
			web = True
			surfaces += 1
		elif dest["type"] == "device":
			surfaces += 1
		elif dest["type"] == "rss":
			feeds += 1

	existing_notif = mochi.db.row(
		"select id from notifications where app = 'notifications' and topic = 'test' and object = ?",
		str(id)
	)
	notif_id = existing_notif["id"] if existing_notif else mochi.uid()
	content = title + ": " + body
	sent = 0
	failed = 0
	if surfaces or feeds:
		# The topics row routes the test tuple through this category, so the
		# bell, each device's list and the RSS join all apply their real
		# filters to it. function_topic_list hides the tuple from the Topics
		# tab - it is test plumbing, not a subscription.
		row_merge("topics", {
			"app": "notifications", "topic": "test", "object": str(id),
			"name": cat["label"], "label": title, "category": str(id), "created": now,
		})
		# State-style: fixed=1 so the stored count of 1 is shown as-is.
		row_merge("notifications", {
			"id": notif_id, "app": "notifications", "topic": "test", "object": str(id),
			"title": title, "body": body, "content": content,
			"link": "/settings/user/notifications", "sender": "",
			"count": 1, "created": now, "read": 0, "fixed": 1,
		})
		# The websocket event goes out from the commit hook, after the row is
		# committed. Emitting inline raced the bell: the event landed while
		# this action was still mid-transaction (the account pushes below take
		# a round trip), so a client refetching on it read the old state.
		ensure_commit_hook_registered()
		mochi.db.commit.fire("notifications", "update" if existing_notif else "insert", notif_id)
		# Each surface and feed with the row in reach counts as reached.
		sent += surfaces + feeds
	for dest in dests:
		if dest["type"] == "account":
			account_id = dest["target"]
			account_label = account_display_label(account_id)
			if not account_label:
				continue  # stale destination row pointing at a deleted account
			account_body = mochi.app.label("notifications.body.test_via_account", account=account_label)
			push_queue_if_unifiedpush(account_id, "notifications", "test", "", title, account_body, "", notif_id)
			result = mochi.account.notify(
				account=account_id,
				app="notifications",
				category="test",
				object="",
				title=title,
				body=account_body,
				link="",
				id=notif_id
			)
			# Count what core delivered, not what was attempted: an unverified
			# account or a dead token reports nothing sent.
			if result and result.get("sent", 0) > 0:
				sent += 1
			else:
				failed += 1
	return {"sent": sent, "failed": failed, "total": sent + failed, "web": web}

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

# What a destination row can name: the two surfaces (web, and a device by id),
# a push or delivery account, and an RSS feed.
DESTINATION_TYPES = ("web", "device", "account", "rss")

def apply_destinations(category_id, destinations):
	if destinations == None:
		return
	if category_id == "0":
		return
	row_remove("destinations", "category = ?", [category_id])
	for dest in destinations:
		# Service callers can pass arbitrary shapes; skip elements that are
		# not dicts, carry an unknown type, or an over-long target rather
		# than aborting or persisting junk. The settings app rejects these
		# upfront on its own routes and answers 400; this is the backstop for
		# every other caller.
		if type(dest) != "dict":
			continue
		dest_type = dest.get("type", "")
		dest_target = str(dest.get("target", ""))
		if dest_type not in DESTINATION_TYPES or len(dest_target) > 64:
			continue
		row_merge("destinations", {"category": category_id, "type": dest_type, "target": dest_target})

# Topic helpers — used by settings page and notification dropdown

def function_topic_list(context):
	"""List every topic row with the app's display name resolved. The object's
	display name is the stored `name`, which every send supplies and the
	schema 5 migration backfilled for older rows - resolving it here cost one
	mochi.entity.name() per row on every settings page load. The row count is
	the user's own subscribed topics and the settings page renders all of
	them, so this is deliberately unpaginated: a limit would silently drop
	topics the user can otherwise recategorise."""
	# The notifications/test tuples are category-test plumbing, not
	# subscriptions - they route each category's test notification through
	# its own filters and have no place in the user's topic list.
	rows = mochi.db.rows("select * from topics where not (app = 'notifications' and topic = 'test') order by created desc") or []
	if not rows:
		return []
	names = {}
	for entry in mochi.app.list():
		names[entry["id"]] = entry["name"]
		for path in entry.get("paths", []):
			names[path] = entry["name"]
	server = mochi.app.label("notifications.app.server")
	result = []
	for row in rows:
		id = row["app"]
		row["app"] = {
			"id": id,
			"name": server if id == "" else names.get(id, id.capitalize())
		}
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
	devices = mochi.device.list() or []
	return {"accounts": accounts, "feeds": feeds, "devices": devices}

# HTTP action endpoints (settings page calls these via service proxy; kept for direct use too)

def action_categories_list(a):
	return {"data": function_category_list({})}

def action_topics_category_set(a):
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

# Service functions for account management (permission-gated)

def function_accounts_vapid(context):
	# None, not {"key": ""}, when the server has no VAPID key: an empty string
	# is indistinguishable from a real answer by the time it reaches a caller,
	# and both callers refuse on None.
	key = mochi.webpush.key()
	if not key:
		return None
	return {"key": key}

def function_accounts_list(context, capability=""):
	return mochi.account.list(capability) or []

def function_accounts_add(context, type="", **fields):
	provider = provider_get(type)
	if not provider:
		return None
	# 4096 per field: this is the app's only entry point to the account insert
	# (the menu shell reaches it via mochi.service.call), so the bound has to
	# live here rather than in a caller.
	for value in fields.values():
		if len(str(value)) > 4096:
			return None
	# Core aborts on a missing required field - a 500 that mails the operator -
	# so refuse first. providers() declares which fields are required and their
	# types; "email" is core's own email_valid behind mochi.text.valid, so this
	# cannot reject an address the add would have taken, or the reverse.
	for field in provider.get("fields") or []:
		value = fields.get(field.get("name"))
		if field.get("required") and not value:
			return None
		if value and field.get("type") == "email" and not mochi.text.valid(value, "email"):
			return None
	# The browser provider declares no fields at all - its endpoint comes from
	# the JavaScript push subscription rather than a form - so the loop above
	# cannot see it, and core has its own refusal for a missing one.
	if type == "browser" and not fields.get("endpoint"):
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
	mochi.db.execute("delete from queue where account = ?", str(id))
	return mochi.account.remove(id)

# The shape core holds a device id to: the client mints a UUID.
DEVICE_ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"

def device_valid(id):
	if len(id) < 8 or len(id) > 64:
		return False
	for c in id.elems():
		if c not in DEVICE_ALPHABET:
			return False
	return True

# The device a request came from: the id the client asserts in its Device
# header, kept only when it names a device the user has registered. Anything
# else - no header, a client from before devices existed, an id the user has
# forgotten - is a request from no device: reads are unfiltered and a push
# registration is unbound.
def device_header(a):
	id = (a.header("Device") or "").strip()
	if not device_valid(id) or not mochi.device.get(id):
		return ""
	return id

# After a push registration. The account it replaced on the same device, if
# any, carried the destination switches the user set: move them across, then
# drop the dead rows. Join every category only for an account that is new to
# the user - a re-registration keeps what it had, or a phone that was unticked
# everywhere would tick itself back at its next launch.
def push_account_bind(result):
	account_id = str(result["id"])
	superseded = [str(id) for id in (result.get("superseded") or [])]
	for old in superseded:
		mochi.db.execute("update or ignore destinations set target = ? where type = 'account' and target = ?", account_id, old)
		mochi.db.execute("delete from destinations where type = 'account' and target = ?", old)
	if not superseded and not result.get("existing"):
		add_destination_to_categories("account", account_id)

# UnifiedPush registration. endpoint="" is the local distributor: the server
# allocates a path the app appends to its server URL. A set endpoint is a
# third-party distributor (ntfy etc), stored opaque and POSTed to per RFC 8030
# at delivery. device is the registered device the subscription belongs to, or
# "" for none.
def function_push_register(context, label="", auth="", p256dh="", endpoint="", device=""):
	if not auth or not p256dh:
		return None
	# Bound like the accounts paths: over-length registration input is a
	# caller bug, refused outright (real auth is ~22 chars, p256dh ~88).
	if len(auth) > 512 or len(p256dh) > 512 or len(endpoint) > 2048 or len(label) > 256:
		return None

	fields = {"auth": auth, "p256dh": p256dh}
	if label:
		fields["label"] = label
	if device:
		fields["device"] = device

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
	# Inbound endpoint is /notifications/-/push/inbound/<account_id>, guarded by
	# the on-device p256dh keypair (only the matching distributor can decrypt).
	# This app's own route, not the menu's: menu declares no inbound action, so
	# core's catch-all served its SPA and an Application Server read the HTML
	# 200 as a delivered push - the hazard action_push_inbound's docstring
	# describes. It is the route the Android distributor already builds, and it
	# stays path-only because push_queue_if_unifiedpush reads a leading "http"
	# as a foreign distributor.
	if not endpoint:
		path = "/notifications/-/push/inbound/%s" % account_id
		mochi.account.update(account_id, endpoint=path)
		result["endpoint"] = path

	mochi.account.update(account_id, enabled=True)
	push_account_bind(result)
	return result

# Stores an FCM device token keyed by Firebase Installations ID: core upserts,
# so a token refresh updates the row in place and a second device gets its own
# row. label is the device's name; device the registered device, or "".
def push_register_fcm(context, token="", installation="", label="", device=""):
	if not token or not installation:
		return None
	if len(token) > 512 or len(installation) > 256 or len(label) > 256:
		return None
	# The app spells this `installation` on its own routes and in the drain
	# envelope; core's account field is `install_id`, so translate here
	# rather than renaming a core API from an app.
	kwargs = {"token": token, "install_id": installation}
	if label:
		kwargs["label"] = label
	if device:
		kwargs["device"] = device
	result = mochi.account.add("fcm", **kwargs)
	if not result or not result.get("id"):
		return result
	account_id = result["id"]
	mochi.account.update(account_id, enabled=True)
	push_account_bind(result)
	return result

# Devices for the settings page: the list, and forgetting one, which takes the
# push accounts registered from it and their destination switches with it.
def function_device_list(context):
	return mochi.device.list() or []

def function_device_remove(context, id=""):
	if not device_valid(id):
		return False
	accounts = [str(acc["id"]) for acc in (mochi.account.list() or []) if acc.get("device") == id]
	if not mochi.device.remove(id):
		return False
	for account in accounts:
		mochi.db.execute("delete from destinations where type = 'account' and target = ?", account)
	mochi.db.execute("delete from destinations where type = 'device' and target = ?", id)
	return True

# Tells the client its push transport: {"transport": "fcm", "firebase_config":
# {...}} when the admin pasted Firebase config (google-services.json verbatim or
# a flat {project_id, app_id, api_key, messaging_sender_id}), else {"transport":
# "unifiedpush"}.
def push_setup(context):
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
	event = app + "-" + topic + "-" + object

	# Same logical push hitting the queue twice (multi-replica fan-out, or
	# repeat updates to the same coalesced thread) becomes one row with the
	# latest payload — phone gets the latest content on drain. ON CONFLICT
	# replaces payload + created.
	mochi.db.execute(
		"insert into queue (account, event, subscription, payload, created) values (?, ?, ?, ?, ?) on conflict(account, event) do update set payload=excluded.payload, created=excluded.created",
		account_id, event, subscription, payload, mochi.time.now()
	)

# Returns queued unifiedpush rows and sweeps rows older than 7 days. Read-only:
# the phone acks via push_ack after posting, so a crash mid-drain
# re-drains. subscription is client-asserted - a courtesy filter between one
# user's devices, not a boundary.
def push_drain(context, subscription=""):
	now = mochi.time.now()
	# Opportunistic TTL sweep: drop rows older than 7 days, regardless of
	# account or subscriber state. Pattern mirrors the unifiedpush account
	# TTL sweep in api_account_notify (core/server/accounts.go).
	mochi.db.execute(
		"delete from queue where created < ?", now - 7 * 86400
	)
	if subscription:
		rows = mochi.db.rows(
			"select account, event, subscription, payload, created from queue where subscription = ? order by created",
			subscription
		) or []
	else:
		rows = mochi.db.rows(
			"select account, event, subscription, payload, created from queue order by created"
		) or []
	# Drain's own envelope, not the WebSocket's: that one spells the subscription
	# sub_id and carries no event. The client parses the two separately - raw
	# JSON here, Gson there - so a key renamed on one side does not reach the other.
	out = []
	for r in rows:
		out.append({
			"subscription": r["subscription"],
			"payload": r["payload"],
			"event": r["event"],
			"account": r["account"],
		})
	return out

# Deletes the named rows; acking a missing row is a no-op. subscription bounds
# the delete to one device's rows and is client-asserted - a courtesy filter,
# not a security boundary.
def push_ack(context, account_events=None, subscription=""):
	if not account_events:
		return {"acked": 0}
	acked = 0
	for ae in account_events:
		if type(ae) != "dict":
			continue
		account = ae.get("account", "")
		event = ae.get("event", "")
		if not account or not event:
			continue
		if subscription:
			mochi.db.execute(
				"delete from queue where account = ? and event = ? and subscription = ?",
				account, event, subscription
			)
		else:
			mochi.db.execute(
				"delete from queue where account = ? and event = ?",
				account, event
			)
		acked += 1
	return {"acked": acked}

# Client-facing action wrappers.

def action_push_accounts_remove(a):
	"""Remove a push account."""
	id = a.input("id", "").strip()
	if not id or len(id) > 64:
		return a.error.label(400, "errors.invalid_id")
	result = function_accounts_remove(None, id=id)
	return {"data": result or {}}

def action_device_register(a):
	"""Register the calling client's device, or refresh its name. The id is
	the client's own, asserted in the Device header; the label is the device's
	name, sent on every launch so a renamed phone updates itself."""
	id = (a.header("Device") or "").strip()
	label = a.input("label", "").strip()
	if not device_valid(id) or len(label) > 256:
		return a.error.label(400, "errors.invalid_id")
	result = mochi.device.register(id, label)
	# A device with no surface rows joins every category, so a new phone - or
	# one registered before device surfaces existed - starts by showing
	# everything. Judged by the rows, not by whether the device is new: a
	# re-registration must not tick back a category the user unticked.
	if not mochi.db.exists("select 1 from destinations where type = 'device' and target = ?", id):
		add_destination_to_categories("device", id)
	return {"data": result}

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
	result = function_push_register(None, label=label, auth=auth, p256dh=p256dh, endpoint=endpoint, device=device_header(a))
	if not result:
		return a.error.label(500, "errors.registration_failed")
	return {"data": result}

def action_push_register_fcm(a):
	"""Register the client's FCM device token, keyed by Firebase Installations ID."""
	token = a.input("token", "").strip()
	installation = a.input("installation", "").strip()
	if not token or not installation:
		return a.error.label(400, "errors.invalid_subscription")
	label = a.input("label", "").strip()
	result = push_register_fcm(None, token=token, installation=installation, label=label, device=device_header(a))
	if not result:
		return a.error.label(500, "errors.registration_failed")
	return {"data": result}

def action_push_setup(a):
	"""Tell the client which push transport this server prefers. Returns
	{"transport": "fcm", "firebase_config": {...}} when the admin has
	pasted Firebase config into system settings, else
	{"transport": "unifiedpush"}. firebase_config is public-by-design."""
	return {"data": push_setup(None) or {"transport": "unifiedpush"}}

def action_push_inbound(a):
	"""Receive an RFC 8030 push from an external Application Server.
	Deferred — forwards via WebSocket fast-path once the Go side exposes
	a binary-safe write API. Currently returns 501.

	The route stays declared even though nothing implements it: the Android
	distributor hands this URL to third-party UnifiedPush apps, and an
	undeclared action falls through to the catch-all that serves the SPA, so
	the Application Server would read an HTML 200 as a delivered push."""
	return a.error.label(501, "errors.inbound_not_implemented")

def action_push_drain(a):
	"""Return queued unifiedpush events. Read-only: the phone posts push/ack with the
	(account, event) pairs it delivered. subscription=<id> limits to one device."""
	subscription = a.input("subscription", "").strip()
	return {"data": push_drain(None, subscription=subscription) or []}

def action_push_ack(a):
	"""Delete acknowledged rows from the push queue. Body: events=<JSON
	array of {account, event}>. Idempotent — acking a row that no
	longer exists is a no-op (TTL'd, manually cleared, or never queued
	because of a live race)."""
	events_raw = a.input("events", "")
	if not events_raw:
		return {"data": {"acked": 0}}
	events = json.decode(events_raw, None)
	if type(events) != "list" or len(events) > 1000:
		return a.error.label(400, "errors.invalid_subscription")
	subscription = a.input("subscription", "").strip()
	return {"data": push_ack(None, account_events=events, subscription=subscription) or {"acked": 0}}
