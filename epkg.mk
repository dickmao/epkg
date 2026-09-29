EMACS ?= emacs
EPKG_FILES ?= $(shell git ls-files *.el lisp/*.el)
EPKG_EL ?= $(filter %.el,$(EPKG_FILES))
EPKG_MAIN ?= ${firstword ${shell grep -l "(provide " $(EPKG_EL)}}
EPKG_LOAD := $(patsubst %,-L %,$(sort $(patsubst %/,%,$(dir $(EPKG_EL)))))
EPKG_EPKG := $(shell $(EMACS) --batch -l package -f package-initialize --eval "(princ (locate-library \"epkg\"))")
EPKG_DIR := $(shell $(EMACS) --batch -L "$(dir $(EPKG_EPKG))" -l epkg --eval "(defvar epkg-main \"$(EPKG_MAIN)\")" --eval "(princ (epkg-dir))")
EPKG_BATCH := $(EMACS) --batch --init-directory "$(EPKG_DIR)" -L "$(dir $(EPKG_EPKG))" -l epkg --eval "(defvar epkg-main \"$(EPKG_MAIN)\")"
EPKG_NAME := $(shell $(EPKG_BATCH) --eval "(princ (epkg-name))")

.PHONY: epkg-compile
epkg-compile: $(EPKG_FILES)
	$(EPKG_BATCH) \
	  --eval "(setq byte-compile-error-on-warn t)" \
	  -f package-initialize \
	  $(EPKG_LOAD) \
	  -f batch-byte-compile $(EPKG_EL); \
	  (ret=$$? ; rm -f $(EPKG_EL:.el=.elc) && exit $$ret)

.PHONY: epkg-install
epkg-install:
	$(call epkg-install,--init-directory "$(EPKG_DIR)")

.PHONY: epkg-dist-clean
epkg-dist-clean:
	( \
	set -e; \
	rm -rf $(EPKG_DIR)/$(EPKG_NAME); \
	rm -rf $(EPKG_DIR)/$(EPKG_NAME).tar; \
	)

.PHONY: epkg-dist
epkg-dist: epkg-dist-clean $(EPKG_FILES)
	$(EPKG_BATCH) -f epkg-inception
	( \
	set -e; \
	rsync -R $(EPKG_FILES) $(EPKG_DIR)/$(EPKG_NAME) && \
	tar -C $(EPKG_DIR) -cf $(EPKG_DIR)/$(EPKG_NAME).tar $(EPKG_NAME); \
	)

define epkg-install
	$(MAKE) -f $(firstword $(MAKEFILE_LIST)) epkg-dist
	( \
	set -e; \
	$(EMACS) --batch $(1) -l package \
	  -f package-initialize \
	  -f package-refresh-contents \
	  --eval "(ignore-errors (apply (function package-delete) (alist-get (quote $(EPKG_NAME) package-alist))))" \
	  --eval "(package-install-file \"$(EPKG_DIR)/$(EPKG_NAME).tar\")"; \
	)
	$(MAKE) -f $(firstword $(MAKEFILE_LIST)) epkg-dist-clean
endef
