# Mochi notifications app
# Copyright Alistair Cunningham 2024-2025

def database_create():
	mochi.db.execute("""create table notifications (
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
	mochi.db.execute("create index notifications_created on notifications(created)")

def database_upgrade(version):
	if version == 2:
		mochi.db.execute("drop table notifications")
		mochi.db.execute("""create table notifications (
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
	if version == 3:
		mochi.db.execute("create index notifications_created on notifications(created)")

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

def action_list(a):
	function_expire()
	return {"data": function_list()}

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
