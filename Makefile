.PHONY: help setup setup-hooks init deps clean run release publish-release docker-build docker-up docker-down git-push push-and-publish deploy-surface

help:
	@echo "LiveView Surface Template"
	@echo ""
	@echo "Setup (run once in a new clone):"
	@echo "  make setup       - git init (if needed), deps, install githooks"
	@echo "  make setup-hooks - Install git hooks (core.hooksPath = git-hooks)"
	@echo ""
	@echo "Development:"
	@echo "  make deps    - mix deps.get"
	@echo "  make run     - Start Phoenix dev server (mix phx.server)"
	@echo "  make clean   - mix clean"
	@echo ""
	@echo "Docker (for multi-app bundling):"
	@echo "  make docker-build - Build Docker image (release inside container)"
	@echo "  make docker-up    - Start containers (docker-compose up)"
	@echo "  make docker-down  - Stop containers (docker-compose down)"
	@echo ""
	@echo "Release & Deploy:"
	@echo "  make release         - Build OTP release locally"
	@echo "  make publish-release - Build, tarball, and publish to GitHub"
	@echo "  make git-push        - Push to origin main (triggers pre-push: build release, publish)"
	@echo "  make push-and-publish - git push + explicit publish-release"
	@echo "  make deploy-surface  - Deploy to production via bot_army_infra"
	@echo ""

setup: init deps setup-hooks
	@echo "✓ Setup complete. Run 'make run' to start; push to main to build and publish release."

setup-hooks:
	@git config core.hooksPath git-hooks
	@echo "✓ Git hooks installed (core.hooksPath = git-hooks)"

init:
	@if [ ! -d .git ]; then git init; echo "Git initialized."; else echo "Git already initialized."; fi

deps:
	mix deps.get

compile:
	mix compile

test:
	mix test

run: deps compile
	@echo "Starting Phoenix dev server..."
	mix phx.server

clean:
	mix clean

release:
	MIX_ENV=prod mix release --overwrite
	@scripts/prune_release_artifacts.sh --build-tree --apply
	@echo "✓ Release built in _build/prod/rel/"

prune-releases:
	@scripts/prune_release_artifacts.sh $(if $(APPLY),--apply,)
	@echo ""
	@echo "  Dry run by default. Add APPLY=1 to delete:  make prune-releases APPLY=1"

publish-release: release
	@echo "Publishing to GitHub..."
	@RELEASE_NAME="surface_liveview_template"; \
	VERSION=$$(cat _build/prod/rel/$$RELEASE_NAME/releases/start_erl.data | awk '{print $$2}'); \
	tar -czf $$RELEASE_NAME-$$VERSION.tar.gz -C _build/prod/rel $$RELEASE_NAME/; \
	gh release create v$$VERSION $$RELEASE_NAME-$$VERSION.tar.gz --draft=false; \
	echo "✓ Published v$$VERSION"

docker-build:
	docker-compose build
	@echo "✓ Docker image built"

docker-up:
	docker-compose up -d
	@echo "✓ Containers started (run 'make docker-down' to stop)"

docker-down:
	docker-compose down
	@echo "✓ Containers stopped"

push: test compile
	@echo "✅ All validations passed"
	@echo "$$(date +%s)" > .push-validated
	@echo "✓ Proof-of-validation created"
	@git push origin main

git-push:
	@SURFACE_NAME=surface_liveview_template; \
	LOG_FILE="/tmp/.git-push-$$SURFACE_NAME-$$-$$(date +%s).log"; \
	echo "📋 Logging to: $$LOG_FILE" && \
	echo "=== GIT PUSH ($$SURFACE_NAME) ===" > "$$LOG_FILE" && \
	echo "Timestamp: $$(date)" >> "$$LOG_FILE" && \
	echo "Surface: $$SURFACE_NAME" >> "$$LOG_FILE" && \
	echo "" >> "$$LOG_FILE" && \
	if git push -u origin main >> "$$LOG_FILE" 2>&1; then \
		echo "✅ Push succeeded"; \
		echo "✅ PUSH COMPLETE" >> "$$LOG_FILE"; \
	else \
		echo "❌ Push failed (see log)"; \
		echo "❌ PUSH FAILED" >> "$$LOG_FILE"; \
		tail -30 "$$LOG_FILE"; \
		exit 1; \
	fi && \
	echo "📋 Full log: $$LOG_FILE"

push-and-publish: git-push publish-release
	@echo "✓ Pushed and published successfully"

deploy-surface:
	@INFRA_DIR=$$(cd $(CURDIR) && while [ ! -d "bots/bot_army_infra" ]; do cd ..; done; pwd)/bots/bot_army_infra; \
	$(MAKE) -C $$INFRA_DIR deploy-surface SURFACE=surface_liveview_template
