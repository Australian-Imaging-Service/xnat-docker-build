IMAGE_TAG := 1.8.10-rc.1

CONFIG = .env
ifneq (,$(wildcard ${CONFIG}))
include ${CONFIG}
endif

DATE := $(shell date '+%Y%m%d%H%M%S')

.PHONY : all build
all : build

.ONESHELL:
SHELL = /bin/bash
build :
	docker buildx build \
		--progress=plain \
		--tag localhost:32000/xnat:${IMAGE_TAG} . 2>&1 \
		|tee log-buildx-$(DATE)
	docker push localhost:32000/xnat:${IMAGE_TAG}
