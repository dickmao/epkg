export VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null || echo 0.0.1)
SHELL := /bin/bash
EMACS ?= emacs
ELSRC := $(shell git ls-files epkg*.el)
MKSRC := $(shell git ls-files epkg*.mk)
TESTSRC := $(shell git ls-files test*.el)

.PHONY: compile
compile:
	$(EMACS) -batch \
	  --eval "(setq byte-compile-error-on-warn t)" \
	  --eval "(push 'no-byte-compile ignored-local-variables)" \
	  -f batch-byte-compile $(ELSRC) $(TESTSRC); \
	  (ret=$$? ; rm -f $(ELSRC:.el=.elc) $(TESTSRC:.el=.elc) && exit $$ret)

.PHONY: test
test: compile
	$(EMACS) --batch \
	  -f package-initialize \
	  -L . $(patsubst %.el,-l %,$(notdir $(TESTSRC))) \
	  -f ert-run-tests-batch

.PHONY: dist-clean
dist-clean:
	( \
	set -e; \
	PKG_NAME=`$(EMACS) -batch -L . -l epkg-package --eval "(princ (epkg-package-name))"`; \
	rm -rf $${PKG_NAME}; \
	rm -rf $${PKG_NAME}.tar; \
	)

.PHONY: dist
dist: dist-clean
	$(EMACS) -batch -L . -l epkg-package -f epkg-package-inception
	( \
	set -e; \
	PKG_NAME=`$(EMACS) -batch -L . -l epkg-package --eval "(princ (epkg-package-name))"`; \
	rsync -R $(ELSRC) $(MKSRC) $${PKG_NAME} && \
	tar cf $${PKG_NAME}.tar $${PKG_NAME}; \
	)

.PHONY: install
install:
	$(MAKE) dist
	( \
	set -e; \
	PKG_NAME=`$(EMACS) -batch -L . -l epkg-package --eval "(princ (epkg-package-name))"`; \
	$(EMACS) --batch -l package \
	  -f package-initialize \
	  --eval "(ignore-errors (apply (function package-delete) (alist-get (quote epkg) package-alist)))" \
	  --eval "(package-install-file \"$${PKG_NAME}.tar\")"; \
	)
	$(MAKE) dist-clean

.PHONY: retag
retag:
	2>/dev/null git tag -d $(VERSION) || true
	2>/dev/null git push --delete origin $(VERSION) || true
	git tag $(VERSION)
	git push origin $(VERSION)
