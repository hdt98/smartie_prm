/**
 * OpenViking Memory Plugin for OpenCode
 * 
 * Direct integration with OpenViking for enterprise document search.
 * Provides tools: memsearch, memread, membrowse
 * 
 * Based on: https://github.com/volcengine/OpenViking/blob/main/examples/opencode-memory-plugin/
 */

import type { Hooks, PluginInput } from "@opencode-ai/plugin"
import { tool } from "@opencode-ai/plugin"
import * as fs from "fs"
import * as path from "path"
import { fileURLToPath } from "url"

const z = tool.schema
const pluginFilePath = fileURLToPath(import.meta.url)
const pluginFileDir = path.dirname(pluginFilePath)

// ============================================================================
// Configuration
// ============================================================================

interface OpenVikingConfig {
  endpoint: string
  apiKey: string
  enabled: boolean
  timeoutMs: number
}

const DEFAULT_CONFIG: OpenVikingConfig = {
  endpoint: "http://localhost:1934",
  apiKey: "",
  enabled: true,
  timeoutMs: 30000,
}

function loadConfig(): OpenVikingConfig {
  const configPath = path.join(pluginFileDir, "openviking-config.json")

  try {
    if (fs.existsSync(configPath)) {
      const fileContent = fs.readFileSync(configPath, "utf-8")
      const fileConfig = JSON.parse(fileContent)
      return {
        ...DEFAULT_CONFIG,
        ...fileConfig,
      }
    }
  } catch (error) {
    console.warn(`Failed to load OpenViking config from ${configPath}:`, error)
  }

  // Check environment variable
  const config = { ...DEFAULT_CONFIG }
  if (process.env.OPENVIKING_API_KEY) {
    config.apiKey = process.env.OPENVIKING_API_KEY
  }
  if (process.env.OPENVIKING_ENDPOINT) {
    config.endpoint = process.env.OPENVIKING_ENDPOINT
  }

  return config
}

// ============================================================================
// Types
// ============================================================================

interface OpenVikingResponse<T = unknown> {
  status: string
  result?: T
  error?: string | { code?: string; message?: string; details?: Record<string, unknown> }
  time?: number
  usage?: Record<string, number>
}

interface SearchResult {
  memories: any[]
  resources: any[]
  skills: any[]
  total: number
  query_plan?: string
}

// ============================================================================
// HTTP Client
// ============================================================================

async function makeRequest<T = any>(
  config: OpenVikingConfig, 
  options: {
    method: "GET" | "POST"
    endpoint: string
    body?: any
  }
): Promise<T> {
  const url = `${config.endpoint}${options.endpoint}`
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  }

  if (config.apiKey) {
    headers["X-API-Key"] = config.apiKey
  }

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), config.timeoutMs)

  try {
    const response = await fetch(url, {
      method: options.method,
      headers,
      body: options.body ? JSON.stringify(options.body) : undefined,
      signal: controller.signal,
    })

    clearTimeout(timeout)

    if (!response.ok) {
      const errorText = await response.text()
      throw new Error(`Request failed (${response.status}): ${errorText}`)
    }

    return (await response.json()) as T
  } catch (error: any) {
    clearTimeout(timeout)
    if (error.name === "AbortError") {
      throw new Error(`Request timeout after ${config.timeoutMs}ms`)
    }
    if (error.message?.includes("fetch failed") || error.code === "ECONNREFUSED") {
      throw new Error(
        `OpenViking service unavailable at ${config.endpoint}. Please check if the service is running.`,
      )
    }
    throw error
  }
}

function unwrapResponse<T>(response: OpenVikingResponse<T>): T {
  if (!response || typeof response !== "object") {
    throw new Error("OpenViking returned an invalid response")
  }
  if (response.status && response.status !== "ok") {
    const errorMsg = typeof response.error === "string" 
      ? response.error 
      : response.error?.message || "Unknown error"
    throw new Error(errorMsg)
  }
  return response.result as T
}

// ============================================================================
// Health Check
// ============================================================================

async function checkServiceHealth(config: OpenVikingConfig): Promise<boolean> {
  try {
    const response = await fetch(`${config.endpoint}/health`, {
      method: "GET",
      signal: AbortSignal.timeout(3000),
    })
    return response.ok
  } catch {
    return false
  }
}

// ============================================================================
// Plugin Tools
// ============================================================================

export const OpenVikingPlugin = async (input: PluginInput): Promise<Hooks> => {
  const config = loadConfig()

  if (!config.enabled) {
    console.log("OpenViking Plugin is disabled in configuration")
    return {}
  }

  console.log(`OpenViking Plugin initialized with endpoint: ${config.endpoint}`)

  const healthy = await checkServiceHealth(config)
  if (!healthy) {
    console.warn(`OpenViking health check failed at ${config.endpoint}`)
  }

  return {
    tool: {
      memsearch: tool({
        description:
          "Search across enterprise documents in OpenViking.\n\n" +
          "Use this tool to find relevant documents, policies, or information.\n" +
          "Returns matching resources with content snippets and relevance scores.\n\n" +
          "Example queries: 'tax policy', 'employee benefits', 'company policy'",
        args: {
          query: z
            .string()
            .describe("Search query in natural language"),
          limit: z
            .number()
            .optional()
            .describe("Maximum number of results (default: 10)"),
        },
        async execute(args, context) {
          console.log(`[memsearch] Query: ${args.query}`)

          try {
            const response = await makeRequest<OpenVikingResponse<SearchResult>>(config, {
              method: "POST",
              endpoint: "/api/v1/search/search",
              body: {
                query: args.query,
                limit: args.limit || 10,
              },
            })

            const result = unwrapResponse(response)
            
            if (!result.resources || result.resources.length === 0) {
              return "No results found for your query."
            }

            const formatted = result.resources.slice(0, args.limit || 10).map((r: any) => ({
              id: r.id,
              content: r.content?.substring(0, 200) + "...",
              score: r._score,
            }))

            return JSON.stringify({
              total: result.total,
              results: formatted,
            }, null, 2)
          } catch (error: any) {
            console.error(`[memsearch] Error: ${error.message}`)
            return `Error: ${error.message}`
          }
        },
      }),

      memread: tool({
        description:
          "Read the full content of a specific document from OpenViking.\n\n" +
          "Use this after finding a document ID from memsearch to read its full content.\n" +
          "Returns the complete document text.",
        args: {
          uri: z
            .string()
            .describe("Document URI (e.g., viking://resources/folder/doc.md)"),
        },
        async execute(args, context) {
          console.log(`[memread] URI: ${args.uri}`)

          try {
            const response = await makeRequest<OpenVikingResponse<string>>(config, {
              method: "GET",
              endpoint: `/api/v1/content/read?uri=${encodeURIComponent(args.uri)}`,
            })

            const content = unwrapResponse(response)
            return content || "No content found at this URI."
          } catch (error: any) {
            console.error(`[memread] Error: ${error.message}`)
            return `Error: ${error.message}`
          }
        },
      }),

      membrowse: tool({
        description:
          "Browse the OpenViking document structure.\n\n" +
          "Use this to explore available documents and folders.\n" +
          "Returns a list of resources and their structure.",
        args: {
          uri: z
            .string()
            .optional()
            .describe("Base URI to browse (default: viking://resources/)"),
        },
        async execute(args, context) {
          const uri = args.uri || "viking://resources/"
          console.log(`[membrowse] URI: ${uri}`)

          try {
            const response = await makeRequest<OpenVikingResponse<any>>(config, {
              method: "GET",
              endpoint: `/api/v1/fs/list?uri=${encodeURIComponent(uri)}`,
            })

            const result = unwrapResponse(response)
            return JSON.stringify(result, null, 2)
          } catch (error: any) {
            console.error(`[membrowse] Error: ${error.message}`)
            return `Error: ${error.message}`
          }
        },
      }),
    },
  }
}
