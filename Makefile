.PHONY: generate test clean

generate: ## Assemble sample evidence files (static fixtures + dynamic) into .test-output/samples/
	@mkdir -p .test-output
	@bash scripts/generate-samples.sh

test: ## Run sample generator unit tests (requires python3 + PyYAML, no AWS)
	@bash test/sample-generator.test.sh

clean: ## Remove generated test output
	@rm -rf .test-output
