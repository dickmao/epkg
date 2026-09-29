EMACS ?= emacs
# Claude-originated Make tricks:
# X = $(eval X := ...)$(X) computes X once on first use, then overwrites X with the result.
# Targets not referencing EPKG_* (e.g., clean) thus never run emacs or git.
EPKG_FILES ?= $(eval EPKG_FILES := $(shell git ls-files *.el lisp/*.el))$(EPKG_FILES)
EPKG_EL ?= $(filter %.el,$(EPKG_FILES))
EPKG_MAIN ?= ${eval EPKG_MAIN := ${firstword ${shell grep -l "(provide " $(EPKG_EL)}}}${EPKG_MAIN}
EPKG_TEST_EL ?= $(eval EPKG_TEST_EL := $(shell git ls-files test*/*.el))$(EPKG_TEST_EL)

EPKG_EPKG = $(eval EPKG_EPKG := $(shell $(EMACS) -batch -l package -f package-initialize --eval "(princ (locate-library \"epkg\"))"))$(EPKG_EPKG)
EPKG_DIR = $(eval EPKG_DIR := $(shell $(EMACS) -batch -L "$(dir $(EPKG_EPKG))" -l epkg --eval "(defvar epkg-main \"$(EPKG_MAIN)\")" --eval "(princ (epkg-dir))"))$(EPKG_DIR)
EPKG_BATCH = $(EMACS) -batch --init-directory "$(EPKG_DIR)" -L "$(dir $(EPKG_EPKG))" -l epkg --eval "(defvar epkg-main \"$(EPKG_MAIN)\")"
EPKG_NAME = $(eval EPKG_NAME := $(shell $(EPKG_BATCH) --eval "(princ (epkg-name))"))$(EPKG_NAME)
EPKG_NAME_VERSION = $(eval EPKG_NAME_VERSION := $(shell $(EPKG_BATCH) --eval "(princ (epkg-name-version))"))$(EPKG_NAME_VERSION)

.PHONY: epkg-compile
epkg-compile:
	$(EPKG_BATCH) \
	  --eval "(setq byte-compile-error-on-warn t)" \
	  -f package-initialize \
	  $(patsubst %,-L %,$(sort $(patsubst %/,%,$(dir $(EPKG_EL))))) \
	  -f batch-byte-compile $(EPKG_EL); \
	  (ret=$$? ; rm -f $(EPKG_EL:.el=.elc) && exit $$ret)

.PHONY: epkg-install
epkg-install:
	$(call epkg-install)

.PHONY: epkg-install-local
epkg-install-local:
	$(call epkg-install,--init-directory "$(EPKG_DIR)")

.PHONY: epkg-dist-clean
epkg-dist-clean:
	( \
	set -e; \
	rm -rf $(EPKG_DIR)/$(EPKG_NAME_VERSION); \
	rm -rf $(EPKG_DIR)/$(EPKG_NAME_VERSION).tar; \
	)

.PHONY: epkg-dist
epkg-dist: epkg-dist-clean
	$(EPKG_BATCH) -f epkg-inception
	( \
	set -e; \
	rsync -R $(EPKG_FILES) $(EPKG_DIR)/$(EPKG_NAME_VERSION) && \
	tar -C $(EPKG_DIR) -cf $(EPKG_DIR)/$(EPKG_NAME_VERSION).tar $(EPKG_NAME_VERSION); \
	)

epkg/requires: FORCE
	$(EPKG_BATCH) -f epkg-requires

FORCE:

.PHONY: epkg-requires-satisfied
epkg-requires-satisfied:
	$(EPKG_BATCH) --eval "(kill-emacs (if (epkg-requires-satisfied-p) 0 1))" \
	  || $(MAKE) -f $(firstword $(MAKEFILE_LIST)) epkg-install-local

# -L of EPKG_EL *after* package-initialize shadows the EPKG_DIR
# installation, thus testing the right thing (the sort removes dups)
.PHONY: epkg-test
epkg-test: epkg/requires epkg-requires-satisfied
	$(EMACS) -batch --init-directory "$(EPKG_DIR)" -f package-initialize \
	  $(patsubst %,-L %,$(sort $(patsubst %/,%,$(dir $(EPKG_EL) $(EPKG_TEST_EL))))) \
	  $(patsubst %.el,-l %,$(notdir $(EPKG_TEST_EL))) \
	  -f ert-run-tests-batch-and-exit

define epkg-install
	$(MAKE) -f $(firstword $(MAKEFILE_LIST)) epkg-dist
	( \
	set -e; \
	$(EMACS) -batch $(1) -l package \
	  -f package-initialize \
	  -f package-refresh-contents \
	  --eval "(ignore-errors (apply (function package-delete) (alist-get (quote $(EPKG_NAME)) package-alist)))" \
	  --eval "(package-install-file \"$(EPKG_DIR)/$(EPKG_NAME_VERSION).tar\")"; \
	)
endef
