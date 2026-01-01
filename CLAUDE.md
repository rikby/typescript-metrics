# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**ts-metrics** is a standalone npm CLI tool for TypeScript code complexity analysis. It wraps the tsg CLI to provide intelligent filtering, color-coded output, and CI/CD integration.

**Key metrics analyzed:**
- **Maintainability Index (MI)**: 0-100 scale (higher is better)
- **Cyclomatic Complexity (CC)**: Decision paths (lower is better)
- **Cognitive Complexity (CoC)**: Mental effort to understand (lower is better)

**Origin**: Extracted from the markdown-ticket project (ticket MDT-112) as a reusable standalone tool.

## Development Commands

### Installation & Dependencies

```bash
# Install the tool globally (for development)
npm install -g typescript-graph  # Required: tsg CLI
npm link                          # Link local package

# System dependencies
brew install jq                   # macOS: JSON processing
sudo apt-get install jq           # Linux (Debian/Ubuntu)
```

### Usage Commands

```bash
# Git diff mode (analyze only changed files)
ts-metrics

# Analyze specific paths
ts-metrics src/
ts-metrics path/to/file.ts

# Output modes
ts-metrics --all src/              # Show all files (disable filtering)
ts-metrics --json src/             # LLM-friendly JSON output
ts-metrics --red src/              # Show only red-zone files
```

### Testing

**No automated test suite exists** - testing is manual/verification-based.

```bash
# Manual testing commands
ts-metrics --json src/ | jq .      # Verify JSON output
ts-metrics src/ > /dev/null; echo $?  # Check exit codes (0/1/2)
```

## Architecture

### Core Implementation

**Pure Bash implementation** - no Node.js runtime dependencies, no build process required.

**Entry point hierarchy:**
```
bin/ts-metrics (executable wrapper)
    └──> run.sh (700-line main implementation)
```

### Key Functions (run.sh)

| Function | Purpose |
|----------|---------|
| `find_project_root()` | Walks up from `$PWD` to find `package.json` or `tsconfig.json` |
| `find_config_file()` | Discovers `.ts-metrics.rc` with fallback hierarchy (project → user → defaults) |
| `discover_tsconfigs()` | Auto-discovers all `tsconfig.json` files in project (excludes `node_modules`, `dist`, hidden dirs) |
| `detect_tsconfig()` | Finds nearest tsconfig for a given file path |
| `discover_changed_files()` | Git diff mode file discovery |
| `calculate_status()` | Determines RED/YLW/GRN zone based on metric thresholds |
| `format_text_table()` | Human-readable output with ANSI colors |
| `run_tsg_metrics()` | Executes tsg CLI and handles errors |
| `main()` | Orchestrates the entire workflow |

### Execution Flow

```
1. Parse CLI flags (--help, --all, --json, --red)
2. Discover project root (walk up from PWD)
3. Load configuration (.ts-metrics.rc hierarchy or built-in defaults)
4. Discover TypeScript files:
   - Git diff mode: Changed files only (default)
   - Path mode: Explicit files/directories
5. Run tsg with discovered tsconfigs
6. Calculate zones (RED/YLW/GRN) based on thresholds
7. Filter output based on flags
8. Format and display (text table or JSON)
9. Exit with appropriate code (0/1/2)
```

### Zone Calculation Logic

Each file is assigned a zone based on its **worst metric**:

```bash
if (MI <= MI_RED_MAX or CC >= CC_RED_MIN or CoC >= COC_RED_MIN):
    zone = "RED"
elif (MI <= MI_YELLOW_MAX or CC >= CC_YELLOW_MIN or CoC >= COC_YELLOW_MIN):
    zone = "YLW"
else:
    zone = "GRN"
```

**Default thresholds** (Microsoft standards):
- MI: YELLOW_MAX=40, RED_MAX=20 (higher is better)
- CC: YELLOW_MIN=11, RED_MIN=21 (lower is better)
- CoC: YELLOW_MIN=11, RED_MIN=21 (lower is better)

### Exit Codes

| Code | Condition | CI/CD Use |
|------|-----------|-----------|
| **0** | No red-zone files | Build passes |
| **1** | Error condition (missing tsg, invalid args) | Configuration issue |
| **2** | Red-zone files detected | Quality gate failure |

## Configuration

### `.ts-metrics.rc` File Location Priority

1. `$PROJECT_ROOT/.ts-metrics.rc` (project-specific, highest priority)
2. `$HOME/.ts-metrics.rc` (user-level fallback)
3. Built-in defaults (Microsoft thresholds)

### Sample Configuration

```bash
# TypeScript configuration directories (relative to project root)
TSCONFIGS=(
  "."           # Root project
  "packages/shared"  # Shared library
  "packages/server"  # Backend server
)

# Maintainability Index (MI) - Higher is better
MI_YELLOW_MAX=40
MI_RED_MAX=20

# Cyclomatic Complexity (CC) - Lower is better
CC_YELLOW_MIN=11
CC_RED_MIN=21

# Cognitive Complexity (CoC) - Lower is better
COC_YELLOW_MIN=11
COC_RED_MIN=21
```

### Auto-Discovery Behavior

If `TSCONFIGS` is empty or omitted in `.ts-metrics.rc`:
- Scans `PROJECT_ROOT` for all `tsconfig.json` files
- Excludes: `node_modules`, `dist`, hidden directories
- Builds `TSCONFIGS` array automatically

## Documentation Priority

**ALWAYS check existing documentation FIRST before answering questions:**

| Question Type | Documentation |
|---------------|--------------|
| "How do I use this?" | `README.md` (Quick Start, Usage) |
| "How does it work?" | `docs/ARCHITECTURE.md` (architecture flow) |
| "What are the specs?" | `docs/SPEC.md` (complete functional specification) |
| "How to refactor code?" | `fix-code-guide.md` (detailed techniques) |
| "Which refactoring technique?" | `fix-code-guide-optimized.md` (decision tree) |
| "How to assess code quality?" | `code-quality-guide.md` (tool-agnostic framework) |

## Important Notes

- **No build process required** - pure Bash script, no compilation
- **No automated tests** - package.json shows placeholder test script only
- **Runtime dependency check**: Script exits with code 1 if `tsg` CLI is not installed, with helpful error message
- **Auto-discovery by default**: Zero-configuration operation for most projects
- **Exit code 2 = quality gate failure**: Used in CI/CD to fail builds on red-zone files
- **JSON output is LLM-friendly**: Structured format for automated processing
