EMACS ?= emacs

# Claude-originated Make trick:
# X = $(call epkg-lazy,X,...) computes X once on first use, thus
# targets not referencing EPKG_* (e.g., clean) never run emacs or git.
epkg-lazy = $(eval $(1) := $(2))$($(1))

EPKG_FILES ?= $(call epkg-lazy,EPKG_FILES,$(shell git ls-files *.el lisp/*.el))
EPKG_EL ?= $(filter %.el,$(EPKG_FILES))
EPKG_MAIN ?= ${call epkg-lazy,EPKG_MAIN,${firstword ${shell grep -l "(provide " $(EPKG_EL)}}}
EPKG_TEST_EL ?= $(call epkg-lazy,EPKG_TEST_EL,$(shell git ls-files test*/*.el))

EPKG_EPKG = $(call epkg-lazy,EPKG_EPKG,$(shell $(EMACS) -batch -l package -f package-initialize --eval "(princ (locate-library \"epkg\"))"))
EPKG_DIR = $(call epkg-lazy,EPKG_DIR,$(shell $(EMACS) -batch -L "$(dir $(EPKG_EPKG))" -l epkg --eval "(defvar epkg-main \"$(EPKG_MAIN)\")" --eval "(princ (epkg-dir))"))
EPKG_INSTALL =
EPKG_BATCH = $(EMACS) -batch --init-directory "$(EPKG_DIR)" -L "$(dir $(EPKG_EPKG))" -l epkg --eval "(defvar epkg-main \"$(EPKG_MAIN)\")"
EPKG_NAME = $(call epkg-lazy,EPKG_NAME,$(shell $(EPKG_BATCH) --eval "(princ (epkg-name))"))
EPKG_NAME_VERSION = $(call epkg-lazy,EPKG_NAME_VERSION,$(shell $(EPKG_BATCH) --eval "(princ (epkg-name-version))"))

.PHONY: epkg-compile
epkg-compile: epkg-old-requires epkg-requires
	$(EPKG_BATCH) \
	  --eval "(setq byte-compile-error-on-warn t)" \
	  -f package-initialize \
	  $(patsubst %,-L %,$(sort $(patsubst %/,%,$(dir $(EPKG_EL))))) \
	  -f batch-byte-compile $(EPKG_EL); \
	  (ret=$$? ; rm -f $(EPKG_EL:.el=.elc) && exit $$ret)

.PHONY: epkg-install
epkg-install: epkg-dist
	$(EMACS) -batch $(EPKG_INSTALL) -l package \
	  -f package-initialize \
	  --eval "(ignore-errors (apply (function package-delete) (alist-get (quote $(EPKG_NAME)) package-alist)))" \
	  -f package-refresh-contents \
	  --eval "(package-install-file \"$(EPKG_DIR)/$(EPKG_NAME_VERSION).tar\")"

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
	$(MAKE) epkg-requires

.PHONY: epkg-requires
epkg-requires:
	$(EPKG_BATCH) --eval "(epkg-sync $(patsubst %,\"%\",$(EPKG_EL)))"
	git add epkg.lock

.PHONY: epkg-old-requires
epkg-old-requires:
	$(EPKG_BATCH) --eval "(kill-emacs (if (epkg-old-requires) 0 1))" \
	  || $(MAKE) epkg-install EPKG_INSTALL='--init-directory "$(EPKG_DIR)"'

# -L of EPKG_EL *after* package-initialize shadows the EPKG_DIR
# installation, thus testing the right thing (the sort removes dups)
.PHONY: epkg-test
epkg-test: epkg/old-requires epkg-old-requires
	$(EMACS) -batch --init-directory "$(EPKG_DIR)" -f package-initialize \
	  $(patsubst %,-L %,$(sort $(patsubst %/,%,$(dir $(EPKG_EL) $(EPKG_TEST_EL))))) \
	  $(patsubst %.el,-l %,$(notdir $(EPKG_TEST_EL))) \
	  -f ert-run-tests-batch-and-exit
