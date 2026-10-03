EMACS ?= emacs

# Claude-originated Make trick:
# X = $(call epkg-lazy,X,...) computes X once on first use, thus
# targets not referencing EPKG_* (e.g., clean) never run emacs or git.
epkg-lazy = $(eval $(1) := $(2))$($(1))

EPKG_FILES ?= $(call epkg-lazy,EPKG_FILES,$(shell git ls-files *.el lisp/*.el))
EPKG_EL ?= $(filter %.el,$(EPKG_FILES))
EPKG_MAIN ?= ${call epkg-lazy,EPKG_MAIN,${firstword ${shell grep -l "(provide " $(EPKG_EL)}}}
EPKG_TEST_EL ?= $(call epkg-lazy,EPKG_TEST_EL,$(shell git ls-files test*/*.el))
EPKG_INSTALL ?=

EPKG_EPKG = $(call epkg-lazy,EPKG_EPKG,$(shell $(EMACS) -batch -l package -f package-initialize --eval "(princ (locate-library \"epkg\"))"))
EPKG_DIR = $(call epkg-lazy,EPKG_DIR,$(shell $(EMACS) -batch -L "$(dir $(EPKG_EPKG))" -l epkg --eval "(defvar epkg-main \"$(EPKG_MAIN)\")" --eval "(princ (epkg-dir))"))
EPKG_BATCH = $(EMACS) -batch --init-directory "$(EPKG_DIR)" -L "$(dir $(EPKG_EPKG))" -l epkg --eval "(defvar epkg-main \"$(EPKG_MAIN)\")"
EPKG_NAME = $(call epkg-lazy,EPKG_NAME,$(shell $(EPKG_BATCH) --eval "(princ (epkg-name))"))
EPKG_NAME_VERSION = $(call epkg-lazy,EPKG_NAME_VERSION,$(shell $(EPKG_BATCH) --eval "(princ (epkg-name-version))"))

.PHONY: epkg-compile
epkg-compile: epkg-package-requires epkg-requires
	$(EPKG_BATCH) \
	  --eval "(setq byte-compile-error-on-warn t)" \
	  -f package-initialize \
	  $(patsubst %,-L %,$(sort $(patsubst %/,%,$(dir $(EPKG_EL))))) \
	  -f batch-byte-compile $(EPKG_EL); \
	  (ret=$$? ; rm -f $(EPKG_EL:.el=.elc) && exit $$ret)

.PHONY: epkg-package-requires
epkg-package-requires:
	$(EPKG_BATCH) --eval "(kill-emacs (if (epkg-package-requires-met) 0 1))" \
	  || $(MAKE) epkg-local-install

.PHONY: epkg-local-install
epkg-local-install:
	$(MAKE) epkg-install EPKG_INSTALL='--init-directory "$(EPKG_DIR)"'
	# so we don't test with it
	rm -rf $(EPKG_DIR)/elpa/$(EPKG_NAME_VERSION)

.PHONY: epkg-install
epkg-install: epkg-requires epkg-dist
	$(EMACS) -batch $(EPKG_INSTALL) -L "$(dir $(EPKG_EPKG))" -l epkg --eval "(defvar epkg-main \"$(EPKG_MAIN)\")" -f epkg-install

.PHONY: epkg-dist-clean
epkg-dist-clean:
	rm -rf $(EPKG_DIR)/$(EPKG_NAME_VERSION) $(EPKG_DIR)/$(EPKG_NAME_VERSION).tar

.PHONY: epkg-dist
epkg-dist: epkg-dist-clean
	$(EPKG_BATCH) -f epkg-inception
	rsync -R $(EPKG_FILES) $(EPKG_DIR)/$(EPKG_NAME_VERSION)
	tar -C $(EPKG_DIR) -cf $(EPKG_DIR)/$(EPKG_NAME_VERSION).tar $(EPKG_NAME_VERSION)

.PHONY: epkg-get
epkg-get:
	$(if $(and $(PKG),$(REV)),,$(error Usage: make epkg-get PKG=pkg REV=rev))
	$(EPKG_BATCH) --eval "(epkg-get '$(PKG) \"$(REV)\")"
	$(MAKE) epkg-requires EPKG_INSTALL='--init-directory "$(EPKG_DIR)"'

.PHONY: epkg-requires
epkg-requires:
	$(EMACS) -batch $(EPKG_INSTALL) -L "$(dir $(EPKG_EPKG))" -l epkg --eval "(defvar epkg-main \"$(EPKG_MAIN)\")" --eval "(epkg-requires $(patsubst %,\"%\",$(EPKG_EL)))"
	git add epkg.lock

.PHONY: epkg-test
epkg-test: epkg-package-requires epkg-requires
	$(EPKG_BATCH) -f package-initialize \
	  $(patsubst %,-L %,$(sort $(patsubst %/,%,$(dir $(EPKG_EL) $(EPKG_TEST_EL))))) \
	  $(patsubst %.el,-l %,$(notdir $(EPKG_TEST_EL))) \
	  -f ert-run-tests-batch-and-exit
