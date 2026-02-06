.PHONY: test test-module clean

# Run all tests in headless mode
test:
	@echo "Running Huginn test suite..."
	@nvim --headless --cmd "set rtp+=." -c "lua require('huginn.tests.run').run_all()"

# Run a single test module (e.g., make test-module MODULE=runner)
test-module:
	@echo "Running Huginn tests for $(MODULE)..."
	@nvim --headless --cmd "set rtp+=." -c "lua require('huginn.tests.run').run('$(MODULE)')"

# Clean generated files
clean:
	@find . -name ".huginnlog" -delete
