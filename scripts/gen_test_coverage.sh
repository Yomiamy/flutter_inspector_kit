#!/usr/bin/env bash
set -euo pipefail

flutter test --coverage --branch-coverage --test-randomize-ordering-seed random
genhtml --ignore-errors source,mismatch,inconsistent coverage/lcov.info -o coverage/html --branch-coverage

# Open the report with the platform's default handler when available; stay
# silent on headless/CI environments where neither launcher exists.
if command -v open >/dev/null 2>&1; then
  open coverage/html/index.html
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open coverage/html/index.html
fi
