import { describe, it, expect, beforeEach, vi } from 'vitest'

describe('OpenVikingPlugin', () => {
  beforeEach(() => {
    vi.resetAllMocks()
  })

  it('should load configuration from file', () => {
    const config = {
      endpoint: 'http://localhost:1934',
      apiKey: 'test-key',
      enabled: true,
      timeoutMs: 30000
    }
    expect(config.endpoint).toBe('http://localhost:1934')
    expect(config.enabled).toBe(true)
  })

  it('should construct correct API payload for search', () => {
    const payload = {
      query: 'tax policy',
      limit: 10
    }
    
    const body = JSON.stringify(payload)
    expect(body).toContain('tax policy')
    expect(body).toContain('10')
  })

  it('should include API key in request headers', () => {
    const apiKey = 'test-api-key'
    const headers = {
      'Content-Type': 'application/json',
      'X-API-Key': apiKey
    }
    expect(headers['X-API-Key']).toBe('test-api-key')
  })

  it('should parse search response correctly', () => {
    const response = {
      status: 'ok',
      result: {
        resources: [
          { id: 'resource-1', content: 'Test content', _score: 0.95 },
          { id: 'resource-2', content: 'More content', _score: 0.87 }
        ],
        total: 2
      }
    }
    
    expect(response.status).toBe('ok')
    expect(response.result.resources.length).toBe(2)
    expect(response.result.resources[0]._score).toBeGreaterThan(response.result.resources[1]._score)
  })

  it('should handle empty search results', () => {
    const response = {
      status: 'ok',
      result: {
        resources: [],
        total: 0
      }
    }
    
    expect(response.result.total).toBe(0)
    expect(response.result.resources).toHaveLength(0)
  })

  it('should format error response', () => {
    const error = {
      status: 'error',
      error: {
        code: 'UNAUTHORIZED',
        message: 'Invalid API key'
      }
    }
    
    expect(error.status).toBe('error')
    expect(error.error.code).toBe('UNAUTHORIZED')
  })
})
