#!/usr/bin/make -f
# -*- coding: utf-8 -*-
#
#    LinOTP - the open source solution for two factor authentication
#    Copyright (C) 2016 KeyIdentity GmbH
#
#    This file is part of LinOTP server.
#
#    This program is free software: you can redistribute it and/or
#    modify it under the terms of the GNU Affero General Public
#    License, version 3, as published by the Free Software Foundation.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the
#               GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#
#    E-mail: linotp@lsexperts.de
#    Contact: www.linotp.org
#    Support: www.lsexperts.de
#
#
# LinOTP toplevel makefile
#
#
# If you are running in a local development environment, you can
# set these environment variables to configure make behaviour:
# export http_proxy=http://proxy.hostname:port
# export no_proxy=localhost,127.0.0.1,.my.local.domain
# export RANCHER_URL=https://rancher.hostname/v1
# export RANCHER_ACCESS_KEY=copy-from-rancher-UI-API-section
# export RANCHER_SECRET_KEY=copy-from-rancher-UI-API-section
# export DOCKER_REGISTRY_URL=registry.local.domain

PYTHON:=python2

# This directory is used as destination for the various parts of
# the build phase. The various install targets default to this directory
# but can be overriden by DESTDIR
BUILDDIR:=$(PWD)/build

# Targets to operate on LinOTPd and its dependent projects shipped
# in this repository
LINOTPD_PROJS := smsprovider useridresolver linotpd adminclient/LinOTPAdminClientCLI

###################
# Recursive targets
#
# These invoke make in the project subdirectories
#
# install
# clean
#
# Each target will be expanded into the subdirectory targets
#
# e.g. build -> build.subdirmake -> build.smsprovider + build.useridresolver + build.linotpd

# Targets that should recurse into linotp project directories
LINOTPD_TARGETS := install clean
.PHONY: $(LINOTPD_TARGETS)

INSTALL_TARGETS := $(addsuffix .install,$(LINOTPD_PROJS))
CLEAN_TARGETS := $(addsuffix .clean,$(LINOTPD_PROJS))
MAKEFILE_TARGETS := $(INSTALL_TARGETS) $(CLEAN_TARGETS)
.PHONY: $(MAKEFILE_TARGETS)

$(MAKEFILE_TARGETS):
	# Invoke makefile target in subdirectory/src
	$(MAKE) -C $(basename $@)/src $(subst $(basename $@).,,$@)

# Subdirectory make that should invoke target in all subproject directories
.PHONY: %.subdirmake
%.subdirmake : smsprovider.% useridresolver.% linotpd.% ;

# Add dependencies for main targets
# build -> build.subdirmake
# clean -> clean.subdirmake
# etc.
.SECONDEXPANSION:
$(LINOTPD_TARGETS): $$(basename $$@).subdirmake

clean:
	if [ -d $(BUILDDIR) ]; then rm -rf $(BUILDDIR) ;fi
	if [ -d RELEASE ]; then rm -rf RELEASE; fi

# Run a command in a list of directories
# $(call run-in-directories,DIRS,COMMAND)
run-in-directories = \
	echo run-in-directories:$(1) ;\
	for P in $(1) ;\
		do \
		    cmd="cd $$P/src && $(2)" ;\
			echo \\n$$cmd ;\
			( eval $$cmd ) || exit $? ;\
	done

# Run a command in all linotpd directories
run-in-linotpd-projs = $(call run-in-directories,$(LINOTPD_PROJS),$(1))

#################
# Targets invoking setup.py
#

# Installation of packages in 'develop mode'.
.PHONY: develop
develop:
	$(call run-in-linotpd-projs,$(PYTHON) setup.py $@)


#####################
# Unit test targets
#
#
# These targets can be run directly from a development
# environment, within a container or an installed system
#
# unittests - just the unit tests
# integrationtests - selenium integration tests
# test - all tests

ifndef NOSETESTS_ARGS
NOSETESTS_ARGS?=-v
endif

test: unittests integrationtests

unittests:
	$(MAKE) -C linotpd/src/linotp/tests/unit $@
	nosetests $(NOSETESTS_ARGS) .

# Functional tests. Additional arguments can be
# supplied with FUNCTIONALTESTS_ARGS
functionaltests:
	$(MAKE) -C linotpd/src/linotp/tests/functional $@

# integrationtests - selenium integration tests
# Use the SELENIUMTESTS_ARGS to supply test arguments
integrationtests:
	$(MAKE) -C linotpd/src/linotp/tests/integration $@

.PHONY: test unittests functionaltests integrationtests


#####################
# Packaging targets
#

# These targets run the various commands needed
# to create packages of linotp

# builddeb: Generate .debs
# deb-install: Build .debs and install to DESTDIR

DEBPKG_PROJS := linotpd useridresolver smsprovider adminclient/LinOTPAdminClientCLI
BUILDARCH = $(shell dpkg-architecture -q DEB_BUILD_ARCH)
CHANGELOG = "$(shell cd linotpd/src ; dpkg-parsechangelog)"

# Output is placed in DESTDIR, but this
# can be overriden
ifndef DESTDIR
DESTDIR = $(BUILDDIR)
endif

.PHONY: builddeb
builddeb:
	# builddeb: Run debuild in each directory to generate .deb
	$(call run-in-directories,$(DEBPKG_PROJS),$(MAKE) builddeb)

.PHONY: deb-install
deb-install: builddeb
	# deb-install: move the built .deb files into an archive directory and
	# 			    generate Packages file
	mkdir -pv $(DESTDIR)
	cp $(foreach dir,$(DEBPKG_PROJS),$(dir)/build/*.deb) $(DESTDIR)
	find $(DESTDIR)
	cd $(DESTDIR) && dpkg-scanpackages -m . > Packages

#####################
# Docker container targets
#
# These targets are for building and running docker containers
# for integration and builds

# Container name | Dockerfile location | Purpose
# ---------------------------------------------------------------------------------------------------
# linotp-builder | Dockerfile.builder             | Container ready to build linotp packages
# linotp         | linotpd/src                    | Runs linotp in apache
# selenium-test  | linotpd/src/tests/integration  | Run LinOTP Selenium tests against selenium remote

# Extra arguments can be passed to docker build
DOCKER_BUILD_ARGS=

# List of tags to add to built linotp images, using the '-t' flag to docker-build
DOCKER_TAGS=latest

# Override to change the mirror used for image building
DEBIAN_MIRROR=ftp.debian.org

# Pass proxy environment variables through to docker build by default
DOCKER_PROXY_BUILD_ARGS= --build-arg=http_proxy --build-arg=https_proxy --build-arg=no_proxy

DOCKER_BUILD_ARGS+= --build-arg=DEBIAN_MIRROR=$(DEBIAN_MIRROR)

# Default Docker run arguments.
# Extra run arguments can be given here. It can also be used to
# override runtime parameters. For example, to specify a port mapping:
#  make docker-run-linotp-sqlite DOCKER_RUN_ARGS='-p 1234:80'
DOCKER_RUN_ARGS=

DOCKER_BUILD = docker build $(DOCKER_BUILD_ARGS) $(DOCKER_PROXY_BUILD_ARGS)
DOCKER_RUN = docker run $(DOCKER_RUN_ARGS)
SELENIUM_TESTS_DIR=linotpd/src/linotp/tests/integration

## Toplevel targets
# Toplevel target to build all containers
docker-build-all: docker-build-debs  docker-build-linotp docker-build-selenium

# Toplevel target to build linotp container
docker-linotp: docker-build-debs  docker-build-linotp

# Build and run Selenium tests
docker-selenium: docker-build-linotp docker-build-selenium docker-run-selenium

##
.PHONY: docker-build-all docker-linotp docker-run-selenium

# This is expanded during build to add image tags
DOCKER_TAG_ARGS=$(foreach tag,$(DOCKER_TAGS),-t $(DOCKER_IMAGE):$(tag))

# The linotp builder container contains all build dependencies
# needed to build linotp, plus a copy of the linotp
# sources under /pkg/linotp
#
# To use this container as a playground to test build linotp:
#   docker run -it linotp-builder
.PHONY: docker-build-linotp-builder
docker-build-linotp-builder:
	$(DOCKER_BUILD) \
		-f Dockerfile.builder \
		-t linotp-builder \
		.

# A unique name to reference containers for this build
NAME_PREFIX := linotpbuilder-$(shell date +%H%M%S-%N)
DOCKER_CONTAINER_NAME = $(NAME_PREFIX)

.PHONY: docker-build-debs
docker-build-debs: docker-build-linotp-builder
	# Force rebuild of debs
	rm -f $(BUILDDIR)/apt/Packages
	$(MAKE) $(BUILDDIR)/apt/Packages

$(BUILDDIR)/apt/Packages:
	# Build the debs in a container, then extract them from the image
	$(DOCKER_RUN) \
		--workdir=/pkg/linotp \
		--name=$(DOCKER_CONTAINER_NAME)-apt \
		--volume=$(PWD):/pkg/linotpsrc:ro \
		linotp-builder \
		sh -c "cp -ra /pkg/linotpsrc/* /pkg/linotp && \
			make deb-install DESTDIR=/pkg/apt DEBUILD_OPTS=\"$(DEBUILD_OPTS)\" "
	docker cp \
		$(DOCKER_CONTAINER_NAME)-apt:/pkg/apt $(DESTDIR)
	docker rm $(DOCKER_CONTAINER_NAME)-apt

.PHONY: docker-build-linotp
docker-build-linotp: DOCKER_IMAGE=linotp
docker-build-linotp: $(BUILDDIR)/dockerfy $(BUILDDIR)/apt/Packages
	cp linotpd/src/Dockerfile \
		linotpd/src/config/*.tmpl \
		linotpd/src/tools/linotp-create-htdigest \
		$(BUILDDIR)

	# We show the files sent to Docker context here to aid in debugging
	find $(BUILDDIR) -ls

	$(DOCKER_BUILD) \
		$(DOCKER_TAG_ARGS) \
		-t $(DOCKER_IMAGE) \
		$(BUILDDIR)

SELENIUM_DB_IMAGE=mysql:latest
.PHONY: docker-build-selenium
docker-build-selenium: docker-build-linotp
	cd $(SELENIUM_TESTS_DIR) \
		&& $(DOCKER_BUILD) \
			-t selenium_tester .
.PHONY: docker-run-selenium
docker-run-selenium: docker-build-selenium
	cd $(SELENIUM_TESTS_DIR) \
		&& docker-compose run --rm selenium_tester
	cd $(SELENIUM_TESTS_DIR) \
		&& docker-compose down

.PHONY: docker-run-linotp-sqlite
docker-run-linotp-sqlite: docker-build-linotp
	# Run linotp in a standalone container
	cd linotpd/src \
		&& $(DOCKER_RUN) -it \
			 -e LINOTP_DB_TYPE=sqlite \
			 -e LINOTP_DB_NAME=//tmp/sqlite \
			 -e LINOTP_DB_HOST= \
			 -e LINOTP_DB_PORT= \
			 -e HEALTHCHECK_PORT=80 \
			 -e APACHE_LOGLEVEL=DEBUG \
			linotp

# Dockerfy tool
.PHONY: get-dockerfy
get-dockerfy: $(BUILDDIR)/dockerfy

DOCKERFY_URL=https://github.com/SocialCodeInc/dockerfy/releases/download/1.1.0/dockerfy-linux-amd64-1.1.0.tar.gz

# Obtain dockerfy binary
# TODO: Build from source
$(BUILDDIR)/dockerfy:
	mkdir -pv $(BUILDDIR)/dockerfy-tmp
	wget --directory-prefix=$(BUILDDIR)/dockerfy-tmp $(DOCKERFY_URL)
	tar -C $(BUILDDIR) -xvf $(BUILDDIR)/dockerfy-tmp/dockerfy-linux-amd64*.gz
	rm -r $(BUILDDIR)/dockerfy-tmp

#####################
# Rancher targets
#
# These targets are for deploying built linotp images to rancher

# Override with ID e.g. branch name, tag or git commit
LINOTP_IMAGE_TAG=$(shell git rev-parse --short HEAD)
RANCHER_STACK_ID=$(shell git rev-parse --short HEAD)

# Override with type, e.g. prod, qa
RANCHER_STACK_TYPE=dev

RANCHER_STACK_NAME=linotp-$(RANCHER_STACK_TYPE)-$(RANCHER_STACK_ID)

DOCKER_REGISTRY=$(subst https://,,$(DOCKER_REGISTRY_URL))

$(BUILDDIR)/rancher/docker-compose.yml:
	$(MAKE) rancher-prepare

rancher-prepare:
	# Overrides to compose file specific to this stack
	mkdir -pv $(BUILDDIR)/rancher
	( echo 'version: "2"' ;\
	  echo 'services:' ;\
	  echo '  linotp:' ;\
	  echo '    image: $(DOCKER_REGISTRY)/linotp:$(LINOTP_IMAGE_TAG)' ;\
	) > $(BUILDDIR)/rancher/docker-compose.yml

RANCHER_COMPOSE=rancher-compose --project-name $(RANCHER_STACK_NAME)
RANCHER_COMPOSE_FILES_LINOTP=-f linotpd/src/docker-compose.yml \
								-f $(BUILDDIR)/rancher/docker-compose.yml

# Uncomment to aid debugging
# export RANCHER_CLIENT_DEBUG=true

# Run a given command
rancher-linotp-do:
	$(RANCHER_COMPOSE) $(RANCHER_COMPOSE_FILES_LINOTP) $(CMD)
.PHONY: rancher-prepare rancher-linotp-do

rancher-linotp-create: rancher-prepare
	$(MAKE) rancher-linotp-do CMD=create

rancher-linotp-rm: $(BUILDDIR)/rancher/docker-compose.yml
	$(MAKE) rancher-linotp-do CMD=rm

rancher-linotp-start: $(BUILDDIR)/rancher/docker-compose.yml
	$(MAKE) rancher-linotp-do CMD="start -d"

rancher-linotp-stop: $(BUILDDIR)/rancher/docker-compose.yml
	$(MAKE) rancher-linotp-do CMD=stop

rancher-linotp-up: $(BUILDDIR)/rancher/docker-compose.yml
	$(MAKE) rancher-linotp-do CMD="up -d"

rancher-linotp-down: $(BUILDDIR)/rancher/docker-compose.yml
	$(MAKE) rancher-linotp-do CMD=down

.PHONY: rancher-linotp-create rancher-linotp-rm
.PHONY: rancher-linotp-start rancher-linotp-stop
.PHONY: rancher-linotp-up rancher-linotp-down
