#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# /*!
# ********************************************************************************
# \file       format_cxx.sh
# \brief      Format modified/added C/C++ files with clang-format.
# \author     Kawanami
# \version    1.0
# \date       28/04/2026
#
# \details
#   Finds files currently modified or added in Git whose extensions match common C/C++
#   suffixes and applies `clang-format -i` to them.
#
# \remarks
#   - Operates only on **modified** or **added** files.
#   - Requires `clang-format` to be available in PATH.
#
# \section format_cxx_sh_version_history Version history
# | Version | Date       | Author   | Description         |
# |:-------:|:----------:|:---------|:--------------------|
# | 1.0     | 28/04/2026 | Kawanami | Initial version.    |
# ********************************************************************************
# */

set -euo pipefail

function usage() {
  echo "Usage: $0 <git-dir>"
  echo
  echo "Arguments:"
  echo "  <git-dir>   Path to the Git repository to format."
}

function err() {
  echo "❌ Error: $*" >&2
  exit 1
}

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

GIT_DIR="$1"

if [ ! -d "$GIT_DIR" ]; then
  err "Git directory does not exist: $GIT_DIR"
fi

CLANG_FORMAT_FLAGS="$GIT_DIR/scripts/clang-format.flags"

if [ ! -f "$CLANG_FORMAT_FLAGS" ]; then
  err "clang-format flag file does not exist: $CLANG_FORMAT_FLAGS"
fi

if ! command -v clang-format >/dev/null 2>&1; then
  err "clang-format not found in PATH"
fi

mapfile -d '' -t FILES < <(
  git -C "$GIT_DIR" ls-files -z -m -o --exclude-standard -- \
    '*.c' '*.cc' '*.cpp' '*.cxx' \
    '*.h' '*.hh' '*.hpp' '*.hxx'
)

if (( ${#FILES[@]} == 0 )); then
  echo "No modified/untracked C/C++ files to format."
  exit 0
fi

echo "Formatting C/C++ files in: $GIT_DIR"
echo "Using flags: $CLANG_FORMAT_FLAGS"
echo

(
  cd "$GIT_DIR"

  clang-format \
    -i \
    -style="file:$CLANG_FORMAT_FLAGS" \
    "${FILES[@]}"
)

echo
echo "✅ C/C++ formatting done."

