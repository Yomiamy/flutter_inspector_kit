#!/usr/bin/env bash
set -euo pipefail

flutter test --coverage --branch-coverage --test-randomize-ordering-seed random
genhtml --ignore-errors source,mismatch,inconsistent coverage/lcov.info -o coverage/html --branch-coverage
open coverage/html/index.html
