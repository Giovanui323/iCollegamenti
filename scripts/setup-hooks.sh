#!/bin/bash
# Configures git to use the repository .githooks directory for local security checks

set -e

chmod +x .githooks/pre-commit
git config core.hooksPath .githooks

echo "✅ Git pre-commit hooks configured successfully."
