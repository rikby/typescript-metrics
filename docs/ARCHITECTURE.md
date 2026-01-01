# ts-metrics Architecture

## Overview

ts-metrics is a wrapper around tsg CLI from typescript-graph, a powerful TypeScript code analysis tool.

It provides:

1. **Multi-tsconfig Support**: Automatically detects which `tsconfig.json` to use based on file paths
2. **Intelligent Filtering**: Shows only files needing attention by default
3. **Status Aggregation**: Combines multiple metrics into overall health status
4. **Exit Code Mapping**: Maps complexity thresholds to CI/CD-friendly exit codes

## Architecture Flow

```
ts-metrics CLI
    │
    ├─> Parse arguments and configuration
    │
    ├─> Detect/discover TypeScript files
    │   ├─> Git diff mode (no paths provided)
    │   └─> Path mode (explicit paths)
    │
    ├─> Run tsg CLI
    │   └─> Collect metrics (MI, CC, CoC)
    │
    └─> Format output
        ├─> Text table (colored, filtered)
        └─> JSON (LLM-friendly)
```

## Components

### Project Root Discovery
- Walks up from `$PWD` to find `package.json` or `tsconfig.json`
- Establishes the base directory for all path resolution

### Configuration Discovery
- Searches for `.ts-metrics.rc` in:
  1. Current directory (walks up to project root)
  2. `$HOME/.ts-metrics.rc` (user-level)
  3. Built-in defaults

### tsconfig Auto-Discovery
- Scans project root for all `tsconfig.json` files
- Excludes: `node_modules`, `dist`, hidden directories
- Builds `TSCONFIGS` array automatically

### Metrics Collection
- Uses `tsg` CLI with discovered tsconfigs
- Supports two modes:
  - **Git diff mode**: Analyzes only changed files
  - **Path mode**: Analyzes specific files/directories

### Zone Calculation
Each file is assigned a zone based on its worst metric:

```
if (MI <= MI_RED_MAX or CC >= CC_RED_MIN or CoC >= COC_RED_MIN):
    zone = "RED"
elif (MI <= MI_YELLOW_MAX or CC >= CC_YELLOW_MIN or CoC >= COC_YELLOW_MIN):
    zone = "YLW"
else:
    zone = "GRN"
```

### Output Filtering
Three filtering modes:

| Mode | Shows Files | Logic |
|------|-------------|-------|
| Default | Yellow + Red | `status !== 'GRN'` |
| `--red` | Red only | `status === 'RED'` |
| `--all` | All zones | `true` |

## Exit Codes

| Code | Condition | Purpose |
|------|-----------|---------|
| 0 | No red-zone files | Success, CI passes |
| 1 | Error condition | Missing tsg, invalid args |
| 2 | Red-zone files detected | CI quality gate fails |

## Dependencies

- **typescript-graph** (tsg CLI): Core TypeScript analysis engine
- **jq**: JSON processing for bash-based filtering
