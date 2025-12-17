# Makefile for Mochi apps
# Copyright Alistair Cunningham 2025

all: web/dist/index.html

clean:
	rm -rf web/dist

web/dist/index.html: $(shell find web/src ../../lib/common/src -type f -newer web/dist/index.html -print 2>/dev/null || true)
	cd web && pnpm run build
