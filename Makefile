# Makefile for Mochi apps
# Copyright Alistair Cunningham 2025

APP = $(notdir $(CURDIR))
VERSION = $(shell grep -m1 '"version"' app.json | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
BUILD = ../../build

all: web/dist/index.html

clean:
	rm -rf web/dist

web/dist/index.html: $(shell find web/src ../../lib/common/src -type f 2>/dev/null)
	cd web && pnpm run build

zip: web/dist/index.html
	mkdir -p $(BUILD)
	rm -f $(BUILD)/$(APP)_*.zip
	zip -r $(BUILD)/$(APP)_$(VERSION).zip app.json *.star labels web/dist
	git tag -a $(VERSION) -m "$(VERSION)"
