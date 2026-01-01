#!/usr/bin/env bash
# ts-metrics: TypeScript Metrics Collection Script
# Complexity analyzer wrapper for tsg CLI
# Standalone npm package version
#
# Last Modified: 2026-01-01
# Target Operating Systems: Linux, macOS, AIX
# Written by: Kurt Thomas and Claude AI
#
# Usage: ts-metrics [OPTIONS] [PATH...]
set -euo pipefail

################################################################################
# GLOBAL VARIABLES (UPPERCASE - read-only, external, or set once)
################################################################################

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PACKAGE_ROOT="$SCRIPT_DIR"

# ANSI color codes (using printf to generate ESC)
readonly RED=$(printf '\033[31m')
readonly YELLOW=$(printf '\033[33m')
readonly GREEN=$(printf '\033[32m')
readonly RESET=$(printf '\033[0m')

# Default values (may be overridden by .ts-metrics.rc)
SHOW_ALL=false
OUTPUT_JSON=false
SHOW_RED_ONLY=false
EXIT_CODE=0
PROJECT_ROOT=""
TSCONFIGS=()

################################################################################
# FUNCTIONS
################################################################################

# Show help message
# Purpose: Display usage information and examples
# Input: None
# Output: Help text to stdout
# Calling functions: None (called directly by user via --help flag)
function show_help() {
  cat << 'EOF'
Usage: ts-metrics [OPTIONS] [PATH...]

TypeScript code metrics analyzer using tsg CLI.

Arguments:
  PATH        Path(s) to analyze. Can be:
              - Absolute path
              - Relative path from project root
              - TypeScript file (.ts)
              - Directory containing .ts files
              If omitted, defaults to git diff mode (changed files only).

Options:
  --help      Show this help message and exit
  --init      Create .ts-metrics.rc configuration file from sample
  --all       Show all files (disable yellow/red filtering)
  --json      Output metrics as JSON instead of text table
  --red       Show only red-zone files (works with --json or text output)

Configuration:
  Configuration is loaded from .ts-metrics.rc in the following priority order:
  1. $PROJECT_ROOT/.ts-metrics.rc (walks up from current directory)
  2. $HOME/.ts-metrics.rc (user-level config)
  3. Built-in defaults

  Configurable thresholds:
    - MI_YELLOW_MAX, MI_RED_MAX: Maintainability Index bounds
    - CC_YELLOW_MIN, CC_RED_MIN: Cyclomatic Complexity bounds
    - COC_YELLOW_MIN, COC_RED_MIN: Cognitive Complexity bounds
    - TSCONFIGS: Array of tsconfig paths (relative to project root)

Exit codes:
  0  Success (no red-zone files found)
  1  Error (invalid arguments, missing dependencies)
  2  Red-zone files detected (for CI/CD gating)

Discovery:
  This script automatically discovers:
  - PROJECT_ROOT: Walks up from $PWD to find package.json or tsconfig.json
  - .ts-metrics.rc: Walks up from $PWD, then checks $HOME
  - TSCONFIGS: Scans PROJECT_ROOT for all tsconfig.json files (excludes
    node_modules, dist, and hidden directories)

Examples:
  ts-metrics                                    # Git diff mode
  ts-metrics src/lib                            # Analyze directory
  ts-metrics src/lib/*.ts                       # Analyze specific files
  ts-metrics --all src                          # Show all files
  ts-metrics --json src                         # JSON output
  ts-metrics --init                             # Create config file

EOF
}

# Initialize configuration file from sample
# Purpose: Create .ts-metrics.rc from .ts-metrics.rc.sample with user interaction
# Input: None (reads from user via prompts)
# Output: Creates .ts-metrics.rc file, exits with code 0 on success or 1 on error
# Calling functions: main() (via --init flag)
function init_config() {
  local target_dir
  local sample_file
  local target_file
  local response

  # Detect git root directory
  local git_root
  git_root="$(git rev-parse --show-toplevel 2>/dev/null)" || true

  # Prompt user for config location
  if [ -n "$git_root" ]; then
    echo "Found git root: $git_root"
    echo "Create .ts-metrics.rc here? [y/n/h/.]"
    echo "  y - yes, create in git root"
    echo "  n - no, decline"
    echo "  h or . - create in current working directory instead"

    while true; do
      read -p "Your choice: " response
      case "$response" in
        y|Y)
          target_dir="$git_root"
          break
          ;;
        n|N)
          echo "Initialization cancelled."
          exit 0
          ;;
        h|H|.)
          target_dir="$PWD"
          break
          ;;
        *)
          echo "Invalid choice. Please enter y, n, h, or ."
          ;;
      esac
    done
  else
    # Not in a git repo, default to CWD
    echo "Not in a git repository."
    echo "Creating .ts-metrics.rc in current working directory: $PWD"
    target_dir="$PWD"
  fi

  # Set file paths
  sample_file="$SCRIPT_DIR/.ts-metrics.rc.sample"
  target_file="$target_dir/.ts-metrics.rc"

  # Check if target already exists
  if [ -f "$target_file" ]; then
    echo "Configuration file already exists: $target_file"
    read -p "Overwrite? [y/n]: " response
    case "$response" in
      y|Y)
        echo "Overwriting existing configuration file."
        ;;
      *)
        echo "Initialization cancelled."
        exit 0
        ;;
    esac
  fi

  # Create config file from sample or minimal default
  if [ -f "$sample_file" ]; then
    # Copy from sample file
    cp "$sample_file" "$target_file"
    if [ $? -eq 0 ]; then
      echo "Configuration file created: $target_file"
      echo "Created from sample: $sample_file"
    else
      echo "Error: Failed to copy sample file." >&2
      exit 1
    fi
  else
    # Create minimal default config
    cat > "$target_file" << 'EOF'
# Configuration for TypeScript metrics analysis
# ts-metrics - Standalone npm package
#
# This file can be placed in:
# 1. $PROJECT_ROOT/.ts-metrics.rc (project-specific, highest priority)
# 2. $HOME/.ts-metrics.rc (user-level, fallback)

# ============================================================================
# TypeScript Configuration Paths
# ============================================================================
# Array of tsconfig directories (relative to project root)
# If commented out or empty, ts-metrics will auto-discover all tsconfig.json
# files in the project (excluding node_modules, dist, and hidden directories)
#
# Default: Auto-discovery (comment out or leave empty to use auto-discovery)
# TSCONFIGS=(
#   "."
#   "shared"
#   "server"
# )

# ============================================================================
# Maintainability Index (MI) Thresholds
# ============================================================================
# Microsoft standard: MI ranges from 0 (worst) to 100 (best)
# Higher values indicate better maintainability
#
# MI_YELLOW_MAX: Files at or below this value are flagged as yellow
# Microsoft yellow zone: 21-40 (moderate maintainability concerns)
MI_YELLOW_MAX=40

# MI_RED_MAX: Files at or below this value are flagged as red
# Microsoft red zone: 0-20 (significant maintainability issues)
MI_RED_MAX=20

# ============================================================================
# Cyclomatic Complexity (CC) Thresholds
# ============================================================================
# Measures control flow complexity based on decision points (if, for, etc.)
# Microsoft standard: Simpler code is easier to maintain
#
# CC_YELLOW_MIN: Files at or above this value are flagged as yellow
# Microsoft yellow zone: 11-20 (moderately complex)
CC_YELLOW_MIN=11

# CC_RED_MIN: Files at or above this value are flagged as red
# Microsoft red zone: 21+ (highly complex, needs refactoring)
CC_RED_MIN=21

# ============================================================================
# Cognitive Complexity (CoC) Thresholds
# ============================================================================
# Measures mental effort to understand code flow (nesting, breaks, etc.)
# Microsoft standard: Lower cognitive load improves readability
#
# COC_YELLOW_MIN: Files at or above this value are flagged as yellow
# Microsoft yellow zone: 11-20 (moderate cognitive effort)
COC_YELLOW_MIN=11

# COC_RED_MIN: Files at or above this value are flagged as red
# Microsoft red zone: 21+ (difficult to understand, simplify logic)
COC_RED_MIN=21
EOF

    if [ $? -eq 0 ]; then
      echo "Configuration file created: $target_file"
      echo "Created with minimal default configuration."
    else
      echo "Error: Failed to create configuration file." >&2
      exit 1
    fi
  fi

  echo "You can now customize the configuration file as needed."
  exit 0
}

# Check if tsg CLI is installed
# Purpose: Verify required dependency is available
# Input: None
# Output: Error message to stderr, exits with code 1 if not found
# Calling functions: main()
function check_tsg_installed() {
  if ! command -v tsg &> /dev/null; then
    echo "Error: tsg CLI is required but not installed." >&2
    echo "Install it with: npm install -g typescript-graph" >&2
    exit 1
  fi
}

# Find project root by walking up directory tree
# Purpose: Discover the TypeScript project root directory
# Input: None (uses $PWD as starting point)
# Output: Absolute path to project root
# Calling functions: main()
function find_project_root() {
  local current_dir="$PWD"

  while [ "$current_dir" != "/" ]; do
    # Check for package.json or tsconfig.json
    if [ -f "$current_dir/package.json" ] || [ -f "$current_dir/tsconfig.json" ]; then
      echo "$current_dir"
      return 0
    fi

    # Move up one directory
    current_dir="$(dirname "$current_dir")"
  done

  # If we reach here, no project root was found
  echo "Error: Cannot find project root (no package.json or tsconfig.json found in $PWD or parent directories)" >&2
  exit 1
}

# Find .ts-metrics.rc configuration file
# Purpose: Discover configuration file with fallback hierarchy
# Input: None
# Output: Absolute path to config file, or empty string if not found
# Calling functions: main()
function find_config_file() {
  local current_dir="$PWD"

  # Walk up from current directory
  while [ "$current_dir" != "/" ]; do
    if [ -f "$current_dir/.ts-metrics.rc" ]; then
      echo "$current_dir/.ts-metrics.rc"
      return 0
    fi

    current_dir="$(dirname "$current_dir")"
  done

  # Check user home directory
  if [ -f "$HOME/.ts-metrics.rc" ]; then
    echo "$HOME/.ts-metrics.rc"
    return 0
  fi

  # No config file found
  echo ""
  return 0
}

# Discover all tsconfig.json files in project
# Purpose: Auto-discover TypeScript project configurations
# Input: $1 - project root directory
# Output: Array of relative paths from project root
# Calling functions: load_config()
function discover_tsconfigs() {
  local tsconfigs=()
  local root="$1"

  # Find all tsconfig.json files, excluding common directories
  while IFS= read -r tsconfig; do
    # Convert to relative path from project root
    local rel_path="${tsconfig#$root/}"
    tsconfigs+=("$rel_path")
  done < <(find "$root" -name "tsconfig.json" \
    -not -path "*/node_modules/*" \
    -not -path "*/dist/*" \
    -not -path "*/.*/*" \
    -not -path "*/.ts-metrics/*" 2>/dev/null | sort)

  # If no tsconfigs found, use default
  if [ ${#tsconfigs[@]} -eq 0 ]; then
    tsconfigs+=(".")
  fi

  echo "${tsconfigs[@]}"
}

# Load configuration from file or built-in defaults
# Purpose: Initialize all configuration variables
# Input: None (reads from global config file or built-in defaults)
# Output: Sets global variables: TSCONFIGS, MI_*, CC_*, COC_*
# Calling functions: main()
function load_config() {
  local config_file
  config_file=$(find_config_file)

  if [ -n "$config_file" ] && [ -f "$config_file" ]; then
    # Source the config file
    source "$config_file"

    # If TSCONFIGS is empty or not set, auto-discover
    if [ -z "${TSCONFIGS:-}" ] || [ ${#TSCONFIGS[@]} -eq 0 ]; then
      mapfile -t TSCONFIGS < <(discover_tsconfigs "$PROJECT_ROOT")
    fi
  else
    # Use built-in defaults with auto-discovered tsconfigs
    mapfile -t TSCONFIGS < <(discover_tsconfigs "$PROJECT_ROOT")

    # Built-in threshold defaults (Microsoft standards)
    MI_YELLOW_MAX=${MI_YELLOW_MAX:-40}
    MI_RED_MAX=${MI_RED_MAX:-20}
    CC_YELLOW_MIN=${CC_YELLOW_MIN:-11}
    CC_RED_MIN=${CC_RED_MIN:-21}
    COC_YELLOW_MIN=${COC_YELLOW_MIN:-11}
    COC_RED_MIN=${COC_RED_MIN:-21}
  fi

  # Validate required variables
  local missing_vars=()
  if [ -z "${MI_YELLOW_MAX:-}" ] || [ -z "${MI_RED_MAX:-}" ]; then
    missing_vars+=("MI_*")
  fi
  if [ -z "${CC_YELLOW_MIN:-}" ] || [ -z "${CC_RED_MIN:-}" ]; then
    missing_vars+=("CC_*")
  fi
  if [ -z "${COC_YELLOW_MIN:-}" ] || [ -z "${COC_RED_MIN:-}" ]; then
    missing_vars+=("COC_*")
  fi

  if [ ${#missing_vars[@]} -gt 0 ]; then
    echo "Error: Invalid configuration. Missing variables: ${missing_vars[*]}" >&2
    exit 1
  fi

  # Validate TSCONFIGS array
  if [ -z "${TSCONFIGS:-}" ] || [ ${#TSCONFIGS[@]} -eq 0 ]; then
    echo "Error: No tsconfig files found in project root: $PROJECT_ROOT" >&2
    exit 1
  fi
}

# Detect nearest ancestor tsconfig for a given path
# Purpose: Find appropriate tsconfig.json for analyzing specific files
# Input: $1 - file or directory path (relative or absolute)
# Output: Relative path to tsconfig directory from project root
# Calling functions: main()
function detect_tsconfig() {
  local path="$1"

  # Convert to absolute path
  if [[ ! "$path" = /* ]]; then
    path="$PROJECT_ROOT/$path"
  fi

  # Check if path exists
  if [ ! -e "$path" ]; then
    echo "Error: Path does not exist: $1" >&2
    exit 1
  fi

  # If path is a file, get its directory
  if [ -f "$path" ]; then
    path="$(dirname "$path")"
  fi

  # Walk up from path to find nearest tsconfig.json
  local current_dir="$path"
  while [ "$current_dir" != "/" ]; do
    if [ -f "$current_dir/tsconfig.json" ]; then
      # Return relative path from project root
      local rel_path="${current_dir#$PROJECT_ROOT/}"
      if [ "$rel_path" = "$current_dir" ]; then
        # current_dir is PROJECT_ROOT
        echo "."
      else
        # Get directory name containing tsconfig.json
        echo "$rel_path"
      fi
      return 0
    fi

    current_dir="$(dirname "$current_dir")"
  done

  # Fallback to root tsconfig
  echo "."
}

# Discover changed files via git
# Purpose: Get list of modified TypeScript files
# Input: None
# Output: Space-separated list of changed .ts files
# Calling functions: main()
function discover_changed_files() {
  local changed_files=()

  # Get tracked changed files
  while IFS= read -r file; do
    changed_files+=("$file")
  done < <(git diff --name-only 2>/dev/null | grep '\.ts$' || true)

  # Get untracked files
  while IFS= read -r file; do
    changed_files+=("$file")
  done < <(git ls-files --others --exclude-standard 2>/dev/null | grep '\.ts$' || true)

  echo "${changed_files[@]}"
}

# Calculate status for a file based on metrics
# Purpose: Determine if file is in green, yellow, or red zone
# Input: $1=MI, $2=CC, $3=CoC values
# Output: "RED", "YLW", or "GRN"
# Calling functions: format_text_table()
function calculate_status() {
  local mi="$1"
  local cc="$2"
  local coc="$3"

  # Check if any metric is in red zone
  if (( $(echo "$mi <= $MI_RED_MAX" | bc -l) )) || \
     [ "$cc" -ge "$CC_RED_MIN" ] || \
     [ "$coc" -ge "$COC_RED_MIN" ]; then
    echo "RED"
  # Check if any metric is in yellow zone
  elif (( $(echo "$mi <= $MI_YELLOW_MAX" | bc -l) )) || \
       [ "$cc" -ge "$CC_YELLOW_MIN" ] || \
       [ "$coc" -ge "$COC_YELLOW_MIN" ]; then
    echo "YLW"
  else
    echo "GRN"
  fi
}

# Get color code for MI value
# Purpose: Return ANSI color code based on MI threshold
# Input: $1=MI value
# Output: ANSI color code or empty string
# Calling functions: format_text_table()
function get_mi_color() {
  local mi="$1"
  if (( $(echo "$mi <= $MI_RED_MAX" | bc -l) )); then
    echo "$RED"
  elif (( $(echo "$mi <= $MI_YELLOW_MAX" | bc -l) )); then
    echo "$YELLOW"
  else
    echo ""
  fi
}

# Get color code for CC value
# Purpose: Return ANSI color code based on CC threshold
# Input: $1=CC value
# Output: ANSI color code or empty string
# Calling functions: format_text_table()
function get_cc_color() {
  local cc="$1"
  if [ "$cc" -ge "$CC_RED_MIN" ]; then
    echo "$RED"
  elif [ "$cc" -ge "$CC_YELLOW_MIN" ]; then
    echo "$YELLOW"
  else
    echo ""
  fi
}

# Get color code for CoC value
# Purpose: Return ANSI color code based on CoC threshold
# Input: $1=CoC value
# Output: ANSI color code or empty string
# Calling functions: format_text_table()
function get_coc_color() {
  local coc="$1"
  if [ "$coc" -ge "$COC_RED_MIN" ]; then
    echo "$RED"
  elif [ "$coc" -ge "$COC_YELLOW_MIN" ]; then
    echo "$YELLOW"
  else
    echo ""
  fi
}

# Check if file should be shown based on filtering
# Purpose: Determine if file passes the filter criteria
# Input: $1=status (RED, YLW, GRN)
# Output: 0 (show) or 1 (hide) as return code
# Calling functions: format_text_table()
function should_show_file() {
  local status="$1"

  if [ "$SHOW_ALL" = true ]; then
    return 0  # Show all files
  fi

  if [ "$SHOW_RED_ONLY" = true ]; then
    # Show only red files
    if [ "$status" = "RED" ]; then
      return 0  # Show file
    fi
    return 1  # Hide file
  fi

  # Default: Show only yellow/red files
  if [ "$status" != "GRN" ]; then
    return 0  # Show file
  fi

  return 1  # Hide file
}

# Run tsg and capture metrics
# Purpose: Execute tsg CLI and handle errors
# Input: $1=tsg command string
# Output: JSON metrics string
# Calling functions: main()
function run_tsg_metrics() {
  local cmd="$1"
  local output

  output=$(eval $cmd 2>&1 | grep -v "^===")

  # Check for missing tsconfig files
  if echo "$output" | grep -q "Cannot find tsconfig"; then
    missing=$(echo "$output" | grep "Cannot find tsconfig" | sed 's/.*Cannot find tsconfig //' | sed 's/ at.*//' | sort -u)
    for tsconfig in $missing; do
      echo "Warning: tsconfig not found: $tsconfig" >&2
    done
    # Continue with available tsconfigs
    output=$($cmd 2>/dev/null || echo '{"metrics":[]}')
  fi

  echo "$output"
}

# Format output as text table
# Purpose: Display metrics in human-readable table format
# Input: $1=JSON metrics string
# Output: Formatted text to stdout, sets global EXIT_CODE
# Calling functions: main()
function format_text_table() {
  local json="$1"

  # Check if there are any metrics using jq
  local metric_count
  metric_count=$(echo "$json" | jq -r '.metrics | length' 2>/dev/null || echo "0")

  if [ "$metric_count" -eq 0 ]; then
    echo "No metrics found."
    return
  fi

  # Print header
  printf "%-60s  %5s  %2s  %3s  %3s\n" "FILE" "MI" "CC" "CoC" "Sts"
  printf "%-60s  %5s  %2s  %3s  %3s\n" "----" "--" "--" "---" "---"

  # Process each file using jq
  local i=0
  while [ $i -lt $metric_count ]; do
    local file=$(echo "$json" | jq -r ".metrics[$i].filePath")
    local mi=$(echo "$json" | jq -r ".metrics[$i].maintainabilityIndex")
    local cc=$(echo "$json" | jq -r ".metrics[$i].cyclomaticComplexity")
    local coc=$(echo "$json" | jq -r ".metrics[$i].cognitiveComplexity")

    # Calculate status
    local status
    status=$(calculate_status "$mi" "$cc" "$coc")

    # Check if should show
    if should_show_file "$status"; then
      # Get color for each metric
      local mi_color=$(get_mi_color "$mi")
      local cc_color=$(get_cc_color "$cc")
      local coc_color=$(get_coc_color "$coc")
      local status_color=""
      case "$status" in
        RED) status_color="$RED" ;;
        YLW) status_color="$YELLOW" ;;
        GRN) status_color="$GREEN" ;;
      esac

      # Truncate file path if needed
      local display_file="$file"
      if [ ${#file} -gt 60 ]; then
        display_file="...${file: -57}"
      fi

      # Print with colored values
      printf "%-60s  ${mi_color}%5s${RESET}  ${cc_color}%2s${RESET}  ${coc_color}%3s${RESET}  ${status_color}%s${RESET}\n" \
        "$display_file" "$mi" "$cc" "$coc" "$status"

      # Track red zone for exit code
      if [ "$status" = "RED" ]; then
        EXIT_CODE=2
      fi
    fi

    i=$((i + 1))
  done
}

# Main execution function
# Purpose: Orchestrate the metrics collection and output
# Input: Global variables from flags and config
# Output: Formatted metrics to stdout, exits with appropriate code
# Calling functions: script entry point
function main() {
  local tsg_cmd
  local tsg_output

  # Discover project root
  PROJECT_ROOT=$(find_project_root)

  # Build tsg command
  if [ ${#PATHS[@]} -eq 0 ]; then
    # Git diff mode
    local changed
    changed=$(discover_changed_files)

    if [ -z "$changed" ]; then
      # No changed files
      if [ "$OUTPUT_JSON" = true ]; then
        echo '{"metrics":[]}'
      else
        echo "No TypeScript files changed."
      fi
      exit 0
    fi

    # Filter to .ts files only
    local ts_files=()
    for file in $changed; do
      if [[ "$file" =~ \.ts$ ]]; then
        ts_files+=("$file")
      fi
    done

    if [ ${#ts_files[@]} -eq 0 ]; then
      if [ "$OUTPUT_JSON" = true ]; then
        echo '{"metrics":[]}'
      else
        echo "No TypeScript files changed."
      fi
      exit 0
    fi

    # Git diff mode: Run tsg ONCE with all tsconfigs and changed files
    # Build file list
    local file_list=""
    for file in "${ts_files[@]}"; do
      file_list="$file_list $file"
    done

    # Run tsg once with all tsconfigs (fast - single invocation)
    tsg_cmd="cd $PROJECT_ROOT && tsg"
    for tsconfig in "${TSCONFIGS[@]}"; do
      # Use explicit tsconfig.json path to prevent recursive directory scan
      local tsconfig_path="$tsconfig/tsconfig.json"
      tsg_cmd="$tsg_cmd --tsconfig $tsconfig_path"
    done
    tsg_cmd="$tsg_cmd --stdout metrics --include $file_list"

    tsg_output=$(run_tsg_metrics "$tsg_cmd")
  else
    # Path mode
    local first_tsconfig
    first_tsconfig=$(detect_tsconfig "${PATHS[0]}")

    # Build file list for --include (paths must be relative to tsconfig directory)
    local include_files=""
    for path in "${PATHS[@]}"; do
      # If tsconfig is in subdirectory, adjust path to be relative to it
      if [ "$first_tsconfig" != "." ]; then
        # Strip tsconfig directory prefix from path
        local rel_path="${path#$first_tsconfig/}"
        # Special case: if path equals tsconfig directory, map to "."
        if [ "$path" = "$first_tsconfig" ]; then
          rel_path="."
        fi
        include_files="$include_files $rel_path"
      else
        # Tsconfig is at root, use path as-is
        include_files="$include_files $path"
      fi
    done

    # Use explicit tsconfig.json path to prevent recursive directory scan
    local tsconfig_path="$first_tsconfig/tsconfig.json"
    tsg_cmd="cd $PROJECT_ROOT && tsg --tsconfig $tsconfig_path --stdout metrics --include $include_files"
    tsg_cmd="$tsg_cmd --exclude dist node_modules '**/*.test.ts' '**/*.spec.ts'"

    # Run tsg for path mode only (git diff mode already set tsg_output)
    tsg_output=$(run_tsg_metrics "$tsg_cmd")

    # Transform filePaths to be relative to project root (not tsconfig directory)
    if [ "$first_tsconfig" != "." ]; then
      tsg_output=$(echo "$tsg_output" | jq "
        .metrics | map(.filePath = \"$first_tsconfig/\" + .filePath) | {metrics: .}
      ")
    fi
  fi

  # Output
  if [ "$OUTPUT_JSON" = true ]; then
    # Add zone field to each metric and filter based on flags
    local filter_expr
    local red_zone_expr

    if [ "$SHOW_RED_ONLY" = true ]; then
      # --red: Show only red zone files
      filter_expr="
        .maintainabilityIndex <= $MI_RED_MAX or
        .cyclomaticComplexity >= $CC_RED_MIN or
        .cognitiveComplexity >= $COC_RED_MIN
      "
    elif [ "$SHOW_ALL" = false ]; then
      # Default: Show yellow and red zone files
      filter_expr="
        .maintainabilityIndex <= $MI_YELLOW_MAX or
        .cyclomaticComplexity >= $CC_YELLOW_MIN or
        .cognitiveComplexity >= $COC_YELLOW_MIN
      "
    else
      # --all: Show all files
      filter_expr="true"
    fi

    # Red zone detection for exit code
    red_zone_expr="
      .maintainabilityIndex <= $MI_RED_MAX or
      .cyclomaticComplexity >= $CC_RED_MIN or
      .cognitiveComplexity >= $COC_RED_MIN
    "

    echo "$tsg_output" | jq -r "
      .metrics | map(
        select($filter_expr) |
        . +
        {
          zone: (
            if (.maintainabilityIndex <= $MI_RED_MAX or
                .cyclomaticComplexity >= $CC_RED_MIN or
                .cognitiveComplexity >= $COC_RED_MIN) then
              \"RED\"
            elif (.maintainabilityIndex <= $MI_YELLOW_MAX or
                  .cyclomaticComplexity >= $CC_YELLOW_MIN or
                  .cognitiveComplexity >= $COC_YELLOW_MIN) then
              \"YLW\"
            else
              \"GRN\"
            end
          )
        }
      ) | {metrics: .}
    " | jq '.'

    # Check for red zone for exit code
    local has_red
    has_red=$(echo "$tsg_output" | jq -r "
      .metrics | map(select($red_zone_expr)) | length
    ")

    if [ "$has_red" -gt 0 ]; then
      EXIT_CODE=2
    fi
  else
    format_text_table "$tsg_output"
  fi

  exit $EXIT_CODE
}

################################################################################
# SCRIPT ENTRY POINT
################################################################################

# Parse flags before main execution
FLAGS=()
PATHS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      show_help
      exit 0
      ;;
    --init)
      init_config
      exit 0
      ;;
    --all)
      SHOW_ALL=true
      shift
      ;;
    --json)
      OUTPUT_JSON=true
      shift
      ;;
    --red)
      SHOW_RED_ONLY=true
      shift
      ;;
    -*)
      echo "Error: Unknown flag: $1" >&2
      echo "Run 'ts-metrics --help' for usage." >&2
      exit 1
      ;;
    *)
      PATHS+=("$1")
      shift
      ;;
  esac
done

# Initialize
check_tsg_installed
load_config

# Run main
main
