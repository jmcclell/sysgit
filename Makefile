.PHONY: help

help:
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help



.build-sentinel: Dockerfile install.sh test-config-repo/.sysgit-bootstrap
	docker buildx build -t sysgit:latest --load . && echo "1" > .build-sentinel

build: .build-sentinel

run: build
	docker run -it --rm sysgit:latest

dev:
	while true; do make run; sleep 1; done

