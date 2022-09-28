.DEFAULT_GOAL := help
SHELL	:= /bin/bash
# COLORS
GREEN	:= $(shell tput -Txterm setaf 2)
YELLOW	:= $(shell tput -Txterm setaf 3)
WHITE	:= $(shell tput -Txterm setaf 7)
RED		:= $(shell tput -Txterm setaf 1)
CYAN	:= $(shell tput -Txterm setaf 6)
RESET	:= $(shell tput -Txterm sgr0)

export AWS_PROFILE ?=
export AWS_REGION ?=
EXAMPLE ?=

OUT_FILE=out.tfstate

## Setup the local env
.env:
	touch .env
	docker-compose run --rm envvars validate
	docker-compose run --rm envvars envfile --overwrite
PHONY: .env

## Check the correct environment variables are set
.check-env:
ifndef EXAMPLE
	$(error EXAMPLE is undefined)
endif
ifndef AWS_PROFILE
	$(error AWS_PROFILE is undefined)
endif
ifndef AWS_REGION
	$(error AWS_REGION is undefined)
endif
PHONY: .check-env

## Regenerate the terraform docs
docs:
	docker-compose run --rm --entrypoint=/bin/sh terraform-docs -c 'terraform-docs .; find ./examples -maxdepth 1 -type d -exec terraform-docs {} \;'
PHONY: docs

## Check the docs via a CI pipeline
docsCheck:
	docker-compose run --rm --entrypoint=/bin/sh terraform-docs -c 'terraform-docs --output-check=true . && find ./examples -maxdepth 1 -type d -exec terraform-docs --output-check=true {} \;'
PHONY: docsCheck

## Format the terraform code
format:
	docker-compose run --rm --entrypoint=/bin/sh terraform  -c 'terraform fmt -recursive'
PHONY: format

## Check the formatting of code via a CI pipeline
formatCheck: .env
	docker-compose run --rm --entrypoint=/bin/sh terraform  -c 'terraform fmt -recursive -check -diff'
PHONY: formatCheck

## Publish changes to github
publish: .env
	docker-compose run --rm envvars ensure --tags publish
	git fetch --all
	git remote add github https://$(GIT_USERNAME):$(GIT_PASSWORD)@github.com/cmdlabs/$(CI_PROJECT_NAME)
	git checkout master
	git pull origin master
	git push --follow-tags github master
	docker-compose run --rm terraform-utils curl -X POST -H 'Content-type: application/json' --data '{"text":"A new commit has been published to Github\nProject: $(CI_PROJECT_NAME)\nRef: $(CI_COMMIT_REF_NAME)\nDiff: https://github.com/cmdlabs/$(CI_PROJECT_NAME)/commit/$(CI_COMMIT_SHA)"}' $(GIT_PUBLISHING_WEBHOOK)
PHONY: publish

###Examples
## Apply the changes for example folder
example.apply: .check-env .env
	docker-compose run --rm terraform sh -c 'cd "./examples/${EXAMPLE}"; terraform apply ${OUT_FILE}; rm -rf ${OUT_FILE}'
PHONY: example.apply

## Destroy the resources from example folder
example.destroy: .check-env .env
	docker-compose run --rm terraform sh -c 'cd "./examples/${EXAMPLE}"; terraform destroy'
PHONY: example.destroy

## Initialise the terraform environment for the example folder
example.init: .env
	docker-compose run --rm terraform sh -c 'cd "./examples/${EXAMPLE}"; terraform init'
PHONY: init

## Plan / view the changes to be made for example folder
example.plan: .check-env .env example.init
	docker-compose run --rm terraform sh -c 'cd "./examples/${EXAMPLE}"; rm -rf ${OUT_FILE}; terraform plan -out ${OUT_FILE}'
PHONY: example.plan

###Help
## Show help
help:
	@echo ''
	@echo ''
	@echo '${CYAN}Usage:${RESET}'
	@echo ''
	@echo '	${YELLOW}make${RESET} ${GREEN}<target>${RESET} ${RED}${RESET}'
	@echo ''
	@echo '${CYAN}Targets:${RESET}'
	@echo ''
	@awk '/(^[a-zA-Z\-\.\_0-9]+:)|(^###[a-zA-Z]+)/ { \
		header = match($$1, /^###(.*)/); \
		if (header) { \
			title = substr($$1, 4, length($$1)); \
			printf "${CYAN}%s${RESET}\n", title; \
		} \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = substr($$1, 0, index($$1, ":")-1); \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
			printf "   ${YELLOW}%-30s${RESET} ${GREEN}%-$(TARGET_MAX_CHAR_NUM)s${RESET}\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST)
