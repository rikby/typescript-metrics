# ts-metrics Specification

## Overview

**ts-metrics** is a standalone npm/npx CLI tool for TypeScript code metrics analysis. It provides complexity analysis with configurable thresholds and LLM-friendly output by wrapping the TypeStatoscope (tsg) CLI.

### Purpose

- Analyze TypeScript code for three key complexity metrics: Maintainability Index (MI), Cyclomatic Complexity (CC), and Cognitive Complexity (CoC)
- Provide intelligent filtering to highlight files needing attention (yellow/red zones)
- Output metrics in both human-readable and LLM-friendly JSON formats
- Support CI/CD gating through exit codes based on code quality thresholds
- Auto-discover project structure and TypeScript configuration files

### Origin

Extracted from the markdown-ticket project (MDT-112) as a reusable standalone tool.

## Installation

### Global Installation

```bash
npm install -g ts-metrics
```

After global installation, the `ts-metrics` command is available system-wide.

### npx Usage (No Installation)

```bash
npx ts-metrics [options] [path...]
```

### Local Project Installation

```bash
npm install --save-dev ts-metrics
```

Add to `package.json` scripts:

```json
{
  "scripts": {
    "metrics": "ts-metrics",
    "metrics:all": "ts-metrics --all src/",
    "metrics:json": "ts-metrics --json src/"
  }
}
```

## Architecture

### Components

```
ts-metrics/
├── bin/
│   └── ts-metrics           # Main CLI entry point
├── lib/
│   ├── config.js            # Configuration discovery and loading
│   ├── project.js           # Project root discovery
│   ├── tsconfig.js          # tsconfig auto-discovery
│   ├── analyzer.js          # Metrics analysis orchestrator
│   └── formatter.js         # Output formatting (text/JSON)
├── docs/
│   └── SPEC.md              # This specification
├── package.json
└── README.md
```

### Dependency

- **TypeStatoscope (tsg)**: Underlying metrics engine
  - Installation: `npm install -g typescript-graph`
  - Required for ts-metrics to function
  - Checked at runtime; helpful error message if missing

### Design Principles

1. **Zero Configuration**: Works out-of-the-box with sensible defaults
2. **Convention over Configuration**: Auto-discovers project structure
3. **Fail-Safe**: Graceful degradation when configs are missing
4. **LLM-Friendly**: JSON output optimized for AI/LLM consumption
5. **CI/CD Ready**: Exit codes support automated quality gates

## Configuration

### Configuration File Discovery Order

The tool searches for configuration files in the following order (first found wins):

1. **`.ts-metrics.rc`** in current working directory
2. **`.ts-metrics.rc`** walking up from current directory to project root
3. **`$HOME/.ts-metrics.rc`** (user-level configuration)
4. **Built-in defaults** (if no config file found)

### Configuration File Format

The `.ts-metrics.rc` file uses bash-like syntax (sourced directly):

```bash
# TypeScript configuration directories to analyze
# Relative paths from project root
TSCONFIGS=(
  "."
  "packages/shared"
  "packages/server"
)

# Maintainability Index (MI) Thresholds
# Range: 0-100, higher is better
MI_YELLOW_MAX=40    # Yellow zone: 21-40
MI_RED_MAX=20       # Red zone: 0-20

# Cyclomatic Complexity (CC) Thresholds
# Higher values indicate more complex control flow
CC_YELLOW_MIN=11    # Yellow zone: 11-20
CC_RED_MIN=21       # Red zone: 21+

# Cognitive Complexity (CoC) Thresholds
# Higher values indicate more mental effort to understand
COC_YELLOW_MIN=11   # Yellow zone: 11-20
COC_RED_MIN=21      # Red zone: 21+
```

### Default Configuration

If no configuration file is found, built-in defaults are used:

```bash
TSCONFIGS=(".")                    # Only root tsconfig.json
MI_YELLOW_MAX=40
MI_RED_MAX=20
CC_YELLOW_MIN=11
CC_RED_MIN=21
COC_YELLOW_MIN=11
COC_RED_MIN=21
```

### Creating a Configuration File

Create `.ts-metrics.rc` in your project root:

```bash
# Copy sample config (if provided)
cp node_modules/ts-metrics/.ts-metrics.rc.sample .ts-metrics.rc

# Or create manually
cat > .ts-metrics.rc << 'EOF'
# Your custom thresholds
MI_YELLOW_MAX=35
CC_YELLOW_MIN=8
EOF
```

## Usage

### Basic Syntax

```bash
ts-metrics [OPTIONS] [PATH...]
```

### Operating Modes

#### 1. Git Diff Mode (Default)

When no paths are provided, analyzes only changed TypeScript files:

```bash
ts-metrics
```

- Analyzes tracked changed files (`git diff --name-only`)
- Analyzes untracked `.ts` files (`git ls-files --others --exclude-standard`)
- Filters to `.ts` files only
- Uses all configured tsconfigs for analysis

#### 2. Path Analysis Mode

When one or more paths are provided, analyzes specific files/directories:

```bash
# Analyze specific directory
ts-metrics src/lib

# Analyze specific file
ts-metrics src/lib/utils.ts

# Analyze multiple paths
ts-metrics src/lib src/components
```

- Auto-detects appropriate tsconfig based on path
- Supports absolute paths
- Supports relative paths from project root
- Supports glob patterns (shell-expanded)

### CLI Options

| Option | Description |
|--------|-------------|
| `--help` | Show usage information and exit |
| `--all` | Show all files, disable yellow/red filtering |
| `--json` | Output metrics as JSON instead of text table |
| `--red` | Show only red-zone files (works with text or JSON output) |
| `--version` | Show version number and exit |

### Exit Codes

| Code | Meaning | Use Case |
|------|---------|----------|
| 0 | Success, no red-zone files found | Normal completion |
| 1 | Error condition | Invalid arguments, missing `tsg`, file not found |
| 2 | Red-zone files detected | CI/CD gating, quality enforcement |

#### CI/CD Integration Example

```bash
#!/bin/bash
# Pre-commit hook or CI step

ts-metrics --json
EXIT_CODE=$?

if [ $EXIT_CODE -eq 2 ]; then
  echo "❌ Red-zone files detected! Please refactor before committing."
  exit 1
elif [ $EXIT_CODE -eq 1 ]; then
  echo "❌ Metrics analysis failed."
  exit 1
else
  echo "✅ Code complexity check passed."
  exit 0
fi
```

## Project Discovery

### Project Root Detection

The tool walks up from the current working directory (`$PWD`) to find the project root by looking for:

1. `package.json` file
2. `tsconfig.json` file

**Search order**: Stop at first match (package.json takes precedence)

**Example**:
```
/Users/user/project/src/lib/utils.ts
  ↑ Walk up
/Users/user/project/src/
  ↑ Walk up
/Users/user/project/package.json  ← Stop here (project root found)
```

### tsconfig Auto-Discovery

When analyzing a path, the tool auto-discovers the appropriate tsconfig:

1. **Path prefix matching**: Map path patterns to tsconfig locations
2. **Nearest tsconfig**: Fallback to nearest `tsconfig.json` in parent directories

**Default path mappings** (configurable):

| Path Pattern | tsconfig Location |
|--------------|-------------------|
| `packages/shared/*` | `packages/shared/tsconfig.json` |
| `packages/server/*` | `packages/server/tsconfig.json` |
| `src/*` or root | `tsconfig.json` |

### Excluded Directories

When auto-discovering tsconfigs, the following directories are excluded:

- `node_modules/`
- `dist/`
- `build/`
- `out/`
- Hidden directories (starting with `.`)

## Output Formats

### Text Table (Default)

Human-readable output with color-coded status:

```
FILE                                                     MI      CC    CoC   Status
-----------------------------------------------------  -------  -----  -----  --------
src/lib/complex-utils.ts                                 22.77    33     54    RED
src/components/form.ts                                   40.88    12     12    YLW
src/utils/helpers.ts                                     65.23     5      6    GRN
```

**Column meanings**:
- **FILE**: Path to analyzed file (truncated to 55 chars)
- **MI**: Maintainability Index (0-100, higher is better)
- **CC**: Cyclomatic Complexity (lower is better)
- **CoC**: Cognitive Complexity (lower is better)
- **Status**: Overall status (RED/YLW/GRN)

**Color coding**:
- Red: Red-zone values
- Yellow: Yellow-zone values
- No color: Green-zone values

**Filtering modes**:
- Default: Show yellow and red zone files
- `--red`: Show only red zone files
- `--all`: Show all files (no filtering)

### JSON Format

LLM-friendly JSON output:

```json
{
  "metrics": [
    {
      "filePath": "src/lib/complex-utils.ts",
      "maintainabilityIndex": 22.77,
      "cyclomaticComplexity": 33,
      "cognitiveComplexity": 54,
      "zone": "RED"
    },
    {
      "filePath": "src/components/form.ts",
      "maintainabilityIndex": 40.88,
      "cyclomaticComplexity": 12,
      "cognitiveComplexity": 12,
      "zone": "YLW"
    },
    {
      "filePath": "src/utils/helpers.ts",
      "maintainabilityIndex": 65.23,
      "cyclomaticComplexity": 5,
      "cognitiveComplexity": 6,
      "zone": "GRN"
    }
  ]
}
```

**Properties**:
- `metrics`: Array of metric objects
- `filePath`: String, full path to analyzed file
- `maintainabilityIndex`: Number, 0-100 scale
- `cyclomaticComplexity`: Number, non-negative integer
- `cognitiveComplexity`: Number, non-negative integer
- `zone`: String, one of `"RED"`, `"YLW"`, or `"GRN"`

**Filtering modes**:
- Default: Include yellow and red zone files
- `--red`: Include only red zone files
- `--all`: Include all files

## Metrics Reference

### Maintainability Index (MI)

**Definition**: Microsoft's composite metric combining Halstead Volume, Cyclomatic Complexity, and Lines of Code.

**Range**: 0-100
- **Higher is better**: Well-maintained, easy to modify
- **Lower is worse**: Difficult to maintain, high risk of bugs

**Thresholds** (Microsoft standard):
- Green: ≥ 41 (well-maintained)
- Yellow: 21-40 (moderate concerns)
- Red: 0-20 (significant issues)

### Cyclomatic Complexity (CC)

**Definition**: Measures control flow complexity based on decision points (if, for, while, catch, etc.).

**Range**: Non-negative integer
- **Lower is better**: Simple, linear control flow
- **Higher is worse**: Complex branching, hard to test

**Thresholds** (Microsoft standard):
- Green: ≤ 10 (simple)
- Yellow: 11-20 (moderately complex)
- Red: ≥ 21 (highly complex)

### Cognitive Complexity (CoC)

**Definition**: Measures mental effort required to understand code flow (nesting, breaks, continues, recursion).

**Range**: Non-negative integer
- **Lower is better**: Easy to read and understand
- **Higher is worse**: Difficult to comprehend, high cognitive load

**Thresholds** (SonarSource standard):
- Green: ≤ 10 (easy to understand)
- Yellow: 11-20 (moderate effort)
- Red: ≥ 21 (difficult to understand)

## Examples

### Development Workflow

```bash
# Check complexity of changed files before committing
ts-metrics

# If red-zone files found, review specific directory
ts-metrics --all src/lib

# Show only red-zone files (needs immediate attention)
ts-metrics --red src/lib

# Get JSON output for LLM code review
ts-metrics --json src/lib | llm review-code

# Get only red-zone files as JSON for CI gating
ts-metrics --red --json src/lib
```

### CI/CD Pipeline

```yaml
# .github/workflows/metrics.yml
name: Code Complexity Check

on: [pull_request]

jobs:
  metrics:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: npm install -g typescript-graph
      - run: npx ts-metrics --json
```

### Monorepo Analysis

```bash
# Analyze specific package
ts-metrics packages/shared/src

# Analyze entire monorepo (all packages)
ts-metrics --all

# Custom config for monorepo structure
cat > .ts-metrics.rc << 'EOF'
TSCONFIGS=(
  "packages/core"
  "packages/server"
  "packages/client"
)
EOF
```

### Find Most Complex Files

```bash
# Show all files sorted by maintainability index
ts-metrics --all --json | \
  jq -r '.metrics | sort_by(.maintainabilityIndex) | .[] | "\(.filePath): \(.maintainabilityIndex)"'
```

## Error Handling

### Missing TypeStatoscope (tsg)

```
Error: tsg CLI is required but not installed.
Install it with: npm install -g typescript-graph
```

**Exit code**: 1

### Missing Configuration File

Behavior: Use built-in defaults (no error)

### Invalid Path Argument

```
Error: Path does not exist: non-existent/path
```

**Exit code**: 1

### Missing tsconfig.json

```
Warning: tsconfig not found: packages/missing/tsconfig.json
```

Behavior: Continues with available tsconfigs, non-fatal warning

### No TypeScript Files

**Git diff mode**: "No TypeScript files changed."
**Path mode**: Empty metrics array

**Exit code**: 0

## Implementation Notes

### Path-to-tsconfig Mapping

When in path analysis mode, the tool maps paths to tsconfigs:

1. **Prefix matching**: Check if path matches configured prefixes
2. **Nearest tsconfig**: Walk up from path to find `tsconfig.json`
3. **Fallback**: Use root `tsconfig.json`

**Example mapping logic**:
```javascript
if (path.startsWith('shared/')) return 'shared/tsconfig.json';
if (path.startsWith('server/')) return 'server/tsconfig.json';
return 'tsconfig.json';
```

### Threshold Filtering Logic

Each file is assigned a zone based on its worst metric:

```javascript
function calculateStatus(mi, cc, coc) {
  const redZone = mi <= MI_RED_MAX || cc >= CC_RED_MIN || coc >= COC_RED_MIN;
  const yellowZone = mi <= MI_YELLOW_MAX || cc >= CC_YELLOW_MIN || coc >= COC_YELLOW_MIN;

  if (redZone) return 'RED';
  if (yellowZone) return 'YLW';
  return 'GRN';
}
```

**Output filtering modes**:

| Mode | Shows Files | Command |
|------|-------------|---------|
| Default | Yellow + Red zones | `ts-metrics` |
| `--red` | Red zone only | `ts-metrics --red` |
| `--all` | All zones (Green + Yellow + Red) | `ts-metrics --all` |

```javascript
function shouldShowFile(status, showRedOnly, showAll) {
  if (showAll) return true;           // --all: show everything
  if (showRedOnly) return status === 'RED';  // --red: red only
  return status !== 'GRN';            // default: yellow + red
}
```

### Performance Considerations

- **Single tsg invocation**: All tsconfigs passed in one command (fast)
- **Git diff mode**: Only analyzes changed files (efficient)
- **Path mode**: Uses `--include` filter to limit analysis scope

## Future Enhancements

### Potential Features

- **Watch mode**: Continuously monitor files and update metrics
- **Historical tracking**: Compare metrics over time
- **Diff output**: Show metric changes between commits
- **Custom metrics**: Support for user-defined complexity rules
- **HTML report**: Generate interactive complexity dashboard
- **VS Code extension**: Visualize metrics in editor

### Configuration Improvements

- **JSON/YAML config**: Alternative to bash syntax
- **Per-file overrides**: Custom thresholds for specific files
- **Ignore patterns**: Exclude specific files/directories
- **Team configs**: Shareable configuration presets

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | TBD | Initial release extracted from markdown-ticket MDT-112 |

## Support

- **Issues**: Report bugs at [repository URL]
- **Documentation**: [repository URL]/blob/main/README.md
- **TypeStatoscope**: https://github.com/TypeScript-Graph/TypeStatoscope
