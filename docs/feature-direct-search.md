# Feature: Direct OpenViking Search Integration

## Problem Statement

Currently, the architecture uses:
- Enterprise Agent (MCP Server) → OpenViking → Qdrant for search
- Indexing Worker → OpenViking → Qdrant for indexing

The OpenViking example shows we can simplify by having OpenCode directly call OpenViking for search, bypassing the MCP server layer.

## Opportunity

From the [OpenViking Memory Plugin](https://github.com/volcengine/OpenViking/blob/main/examples/opencode-memory-plugin/README.md):

> Uses OpenCode's tool mechanism to expose OpenViking capabilities as explicit agent-callable tools.
> - the agent sees concrete tools and decides when to call them
> - OpenViking data is fetched on demand through tool execution instead of being pre-injected into every prompt

The plugin provides:
- `memsearch` - Search across memories, resources, skills
- `memread` - Read content from URI
- `membrowse` - Browse filesystem
- `memcommit` - Trigger memory extraction

## Architecture Options

### Option A: Current Architecture (MCP Server)
```
PRM Desktop → MCP Server → OpenViking → Qdrant
```
- Pros: Full Enterprise Agent features (auth, guardrails, observability)
- Cons: Extra hop for simple search

### Option B: Direct OpenCode + OpenViking
```
PRM Desktop → OpenCode Plugin → OpenViking → Qdrant
```
- Pros: Simpler, direct search access
- Cons: Loses Enterprise Agent features

### Option C: Hybrid (Recommended for MVP1)
Keep MCP server for full features, but also support direct OpenCode plugin for search-only use cases.

## API Key Authorization

OpenViking supports API key authentication with roles:
- `ROOT` - Full administrative access
- `ADMIN` - Account-level admin
- `USER` - Basic user access

For MVP1:
- Configure `root_api_key` in OpenViking
- Use single API key for both search and indexing
- The indexing worker and MCP server share the same OpenViking instance

## Implementation Plan

1. **Update SOLUTION_DESIGN.md** to document both options
2. **Create OpenCode plugin** that calls OpenViking search API directly
3. **Configure OpenViking** with API key for production
4. **Test both paths**: MCP → OV and OpenCode Plugin → OV

## Files to Modify

- `docs/SOLUTION_DESIGN.md` - Document hybrid approach
- Create `openviking/opencode-plugin/` - OpenCode plugin for direct search

## Next Steps

1. Confirm this approach is acceptable
2. Implement OpenCode plugin for search
3. Update documentation
