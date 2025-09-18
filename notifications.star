# Mochi notifications app
# Copyright Alistair Cunningham 2024-2025

def database_create():
	mochi.db.query("create table notifications ( app text not null, category text not null, object text not null, content text not null, link text not null default '', created integer not null, primary key ( app, category, object ) )")
	return 1


def function_clear_all():
	mochi.db.query("delete from notifications")


def function_clear_app(app):
	mochi.db.query("delete from notifications where app=?", app)


#TODO Decide structure
def function_clear_object(app, object):
	mochi.db.query("delete from notifications where app=? and object=?", app, object)


def function_create(app, category, object, content, link):
	if not mochi.text.valid(app, "constant"):
		return

	if not mochi.text.valid(category, "constant"):
		return

	if not mochi.text.valid(object, "path"):
		return

	if not mochi.text.valid(content, "text"):
		return
	
	if not mochi.text.valid(link, "url"):
		return

	mochi.db.query("replace into notifications ( app, category, object, content, link, created ) values ( ?, ?, ?, ?, ?, ? )", app, category, object, content, link, mochi.time.now())


def function_list():
	return mochi.db.query("select * from notifications order by created, content")
