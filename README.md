# typescript-metrics

TypeScript code metrics CLI tool - A wrapper for tsg CLI that provides complexity analysis with configurable thresholds, colored output, and CI/CD integration.

## Features

- **Auto-discovery**: Automatically detects TypeScript files via git diff or explicit paths
- **Colored Output**: Visual indicators (green/yellow/red) for code complexity zones
- **Configurable Thresholds**: Customize maintainability and complexity limits
- **Multiple Output Formats**: Human-readable tables or LLM-friendly JSON
- **CI/CD Integration**: Exit codes for automated quality gates
- **Multi-project Support**: Handles monorepos with multiple tsconfig files
- **Intelligent Filtering**: By default, shows only files needing attention (yellow/red zones)

## Metrics Analyzed

typescript-metrics analyzes three key complexity metrics:

| Metric | Description | Range |
|--------|-------------|-------|
| **Maintainability Index (MI)** | Overall code maintainability | 0-100 (higher is better) |
| **Cyclomatic Complexity (CC)** | Control flow complexity (decision points) | 1+ (lower is better) |
| **Cognitive Complexity (CoC)** | Mental effort to understand code | 1+ (lower is better) |

## Installation

**Prerequisite**: This tool requires `typescript-graph` (tsg CLI) as a peer dependency.

### Global Installation (Recommended)

```bash
npm install -g typescript-metrics typescript-graph
```

**Note**: The `tsm` command is available as a shorthand alias for `typescript-metrics`. Both commands work identically:

```bash
typescript-metrics --help    # Full command name
tsm --help           # Shorthand alias (equivalent)
```

### Using npx (No Installation)

```bash
# Install tsg globally first (required)
npm install -g typescript-graph

# Then use npx for typescript-metrics
npx typescript-metrics [options] [path...]
# or
npx tsm [options] [path...]
```

### Local Installation

```bash
npm install --save-dev typescript-metrics typescript-graph
```

Then add to your `package.json` scripts:

```json
{
  "scripts": {
    "metrics": "typescript-metrics",
    "metrics:all": "typescript-metrics --all src/",
    "tsm": "tsm",
    "tsm:all": "tsm --all src/"
  }
}
```

## Quick Start

**Tip**: Use `tsm` as a shorthand for `typescript-metrics` in all examples below.

### Analyze Changed Files (Git Diff Mode)

```bash
# Analyze only TypeScript files that have changed
typescript-metrics
# or
tsm
```

### Analyze Specific Paths

```bash
# Analyze a directory
typescript-metrics src/
# or
tsm src/

# Analyze specific files
typescript-metrics src/utils/date.ts src/helpers/format.ts

# Show all files (disable filtering)
typescript-metrics --all src/
```

### JSON Output for CI/CD

```bash
# Output metrics as JSON
typescript-metrics --json src/ > metrics.json
# or
tsm --json src/ > metrics.json
```

## Configuration

Create a `.typescript-metrics.rc` file in your project root to customize thresholds and tsconfig paths.

### Sample Configuration

```bash
# .typescript-metrics.rc
# TypeScript configuration directories
TSCONFIGS=(
  "."           # Root project
  "packages/shared"  # Shared library
  "packages/server"  # Backend server
)

# Maintainability Index (MI) - Higher is better
MI_YELLOW_MAX=40    # Yellow zone: <= 40
MI_RED_MAX=20       # Red zone: <= 20

# Cyclomatic Complexity (CC) - Lower is better
CC_YELLOW_MIN=11    # Yellow zone: >= 11
CC_RED_MIN=21       # Red zone: >= 21

# Cognitive Complexity (CoC) - Lower is better
COC_YELLOW_MIN=11   # Yellow zone: >= 11
COC_RED_MIN=21      # Red zone: >= 21
```

## Usage

### Command Syntax

```bash
typescript-metrics [OPTIONS] [PATH...]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `PATH` | Path(s) to analyze. Can be absolute or relative paths. Supports files (`.ts`) or directories containing `.ts` files. If omitted, defaults to git diff mode (analyzes changed files only). |

### Options

| Option | Description |
|--------|-------------|
| `--help` | Show help message and exit |
| `--all` | Show all files (disable yellow/red zone filtering) |
| `--json` | Output metrics as JSON instead of text table |
| `--red` | Show only red-zone files (works with text or JSON output) |

### Examples

#### Git Diff Mode (Default)

```bash
# Analyze only changed TypeScript files
typescript-metrics
```

#### Directory Analysis

```bash
# Analyze specific directory
typescript-metrics src/

# Show all files in directory
typescript-metrics --all src/

# Show only red-zone files (needs immediate attention)
typescript-metrics --red src/

# JSON output for LLM consumption
typescript-metrics --json src/

# JSON output with only red-zone files (for CI gating)
typescript-metrics --red --json src/
```

#### File Analysis

```bash
# Analyze specific file
typescript-metrics src/utils/date.ts

# Analyze multiple files
typescript-metrics src/utils/date.ts src/helpers/format.ts
```

#### CI/CD Integration

```bash
# Fail build if red-zone files detected
typescript-metrics --json src/
if [ $? -eq 2 ]; then
  echo "Error: Red-zone files detected!"
  exit 1
fi
```

## Output Formats

### Text Table (Default)

Human-readable output with colored status indicators:

```
FILE                                                     MI      CC    CoC   Status
-----------------------------------------------------  -------  -----  -----  --------
shared/test-lib/ticket/file-ticket-creator.ts          22.77    33     54    RED
shared/test-lib/ticket/ticket-creator.ts               40.88    12     12    YLW
shared/utils/date.ts                                    67.45     5      3    GRN
```

**Column Legend:**
- **MI**: Maintainability Index (0-100, higher is better)
- **CC**: Cyclomatic Complexity (lower is better)
- **CoC**: Cognitive Complexity (lower is better)
- **Status**: Overall health indicator (GRN/YLW/RED)

### JSON Format

LLM-friendly JSON output for automated processing:

```bash
typescript-metrics --json src/
```

Output:
```json
{
  "metrics": [
    {
      "filePath": "shared/utils/date.ts",
      "maintainabilityIndex": 67.45,
      "cyclomaticComplexity": 5,
      "cognitiveComplexity": 3,
      "zone": "GRN"
    }
  ]
}
```

**Filtering modes**:
- Default: Show yellow + red zones
- `--red`: Show only red zone
- `--all`: Show all zones (green + yellow + red)

## Exit Codes

| Code | Meaning | Use Case |
|------|---------|----------|
| **0** | Success (no red-zone files) | Build passes, code quality acceptable |
| **1** | Error (invalid arguments, missing dependencies) | Configuration issue, missing `tsg` CLI |
| **2** | Red-zone files detected | CI/CD quality gate failure |

### Using Exit Codes in CI/CD

```bash
#!/bin/bash
# Example CI/CD script

typescript-metrics --json
EXIT_CODE=$?

if [ $EXIT_CODE -eq 2 ]; then
  echo "❌ Quality gate failed: Red-zone files detected"
  echo "Please refactor high-complexity files before merging."
  exit 1
elif [ $EXIT_CODE -eq 1 ]; then
  echo "❌ Error running metrics check"
  exit 1
else
  echo "✅ Quality gate passed"
fi
```

## Threshold Zones

### Maintainability Index (MI)

| Zone | Range | Description | Action |
|------|-------|-------------|--------|
| **Green** | ≥ 41 | Well-maintained | No action needed |
| **Yellow** | 21-40 | Moderate concerns | Consider refactoring |
| **Red** | 0-20 | Significant issues | Refactoring required |

### Cyclomatic Complexity (CC)

| Zone | Range | Description | Action |
|------|-------|-------------|--------|
| **Green** | ≤ 10 | Simple control flow | No action needed |
| **Yellow** | 11-20 | Moderately complex | Consider simplifying |
| **Red** | ≥ 21 | Highly complex | Refactoring required |

### Cognitive Complexity (CoC)

| Zone | Range | Description | Action |
|------|-------|-------------|--------|
| **Green** | ≤ 10 | Easy to understand | No action needed |
| **Yellow** | 11-20 | Moderate effort | Consider simplifying |
| **Red** | ≥ 21 | Difficult to understand | Refactoring required |

## CI/CD Integration

### GitHub Actions

```yaml
name: Code Quality Check

on:
  pull_request:
    paths:
      - '**.ts'
      - '**.tsx'

jobs:
  metrics:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: npm install -g typescript-graph
      - run: npx typescript-metrics --json
        # Exit code 2 (red-zone files) will fail the workflow
```

## Dependencies

- **typescript-graph** (tsg CLI): Core TypeScript analysis engine
- **jq**: JSON processing (for text table formatting)

### Installing Dependencies

```bash
# Install tsg (required)
npm install -g typescript-graph

# Install jq (required on macOS/Linux)
# macOS
brew install jq

# Linux (Debian/Ubuntu)
sudo apt-get install jq

# Linux (RHEL/CentOS)
sudo yum install jq
```

## Error Handling

| Error | Cause | Solution |
|-------|-------|----------|
| `tsg: command not found` | typescript-graph not installed | Run `npm install -g typescript-graph` |
| `Cannot find tsconfig` | Missing tsconfig.json | Create tsconfig.json or update `.typescript-metrics.rc` |
| `No TypeScript files changed` | No .ts files in git diff | Modify a .ts file or provide explicit path |
| `Path does not exist` | Invalid path argument | Check path spelling and location |

## Recipes

### Find Most Complex Files

```bash
typescript-metrics --all --json | \
  jq -r '.metrics | sort_by(.maintainabilityIndex) | .[] | "\(.filePath): \(.maintainabilityIndex)"'
```

### Integration with LLMs

```bash
# Feed metrics to Claude, GPT-4, etc.
typescript-metrics --json src/ | \
  jq -r '.metrics[] | "File: \(.filePath)\nMI: \(.maintainabilityIndex), CC: \(.cyclomaticComplexity)\n"' | \
  llm "Review these files and suggest refactoring"
```

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for implementation details.

## License

MIT

## Contributing

Contributions welcome! Please open an issue or submit a pull request.

## Related Projects

- [typescript-graph](https://github.com/ysk8hori/typescript-graph) - TypeScript code analysis and dependency visualization tool

## Support

- **Issues**: Report bugs and feature requests on GitHub
- **Documentation**: See inline help: `typescript-metrics --help`
