include epkg.mk
epkg.mk:
	emacs --batch -l package -f package-initialize -l epkg -f epkg-copy-mk

SHELL := /bin/bash
EMACS ?= emacs

EPKG_FILES := foo-module.so lisp/foo*.el scripts/*.py
EPKG_MAIN := lisp/foo.el
EPKG_TEST_EL := tests/test*.el

foo-module.so: foo.c
	gcc -fPIC -g -shared -o $@ $^

.DEFAULT_GOAL := compile

.PHONY: compile
compile: foo-module.so epkg-compile

.PHONY: test
test: compile epkg-test

.PHONY: install
install: foo-module.so epkg-install
