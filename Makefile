all: web/dist/index.html

web/dist/index.html: $(shell find web/src -type f -newer web/dist/index.html -print 2>/dev/null || true)
	cd web && pnpm run build
