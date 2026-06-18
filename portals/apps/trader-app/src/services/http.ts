import { userManager } from '../oidcUserManager'

interface RequestConfig {
  url: string
  method?: string
  headers?: Record<string, string>
  params?: Record<string, string | number | boolean | undefined | null>
  data?: unknown
  attachToken?: boolean
  signal?: AbortSignal
}

export class HttpError extends Error {
  readonly status: number
  readonly statusText: string
  readonly body: unknown

  constructor(status: number, statusText: string, body: unknown) {
    super(`HTTP error! status: ${status} ${statusText}`)
    this.name = 'HttpError'
    this.status = status
    this.statusText = statusText
    this.body = body
  }
}

const inFlightRequests = new Map<string, Promise<{ data: unknown }>>()

function isPlainObject(value: unknown): boolean {
  return (
    value !== null &&
    typeof value === 'object' &&
    !(value instanceof FormData) &&
    !(value instanceof Blob) &&
    !(value instanceof ArrayBuffer) &&
    !(value instanceof URLSearchParams)
  )
}

export const http = {
  request: async (config: RequestConfig): Promise<{ data: unknown }> => {
    let url = config.url
    if (config.params) {
      const searchParams = new URLSearchParams()
      for (const [key, value] of Object.entries(config.params)) {
        if (value !== undefined && value !== null) {
          searchParams.append(key, String(value))
        }
      }
      const queryString = searchParams.toString()
      if (queryString) {
        url += (url.includes('?') ? '&' : '?') + queryString
      }
    }

    const isGet = !config.method || config.method.toUpperCase() === 'GET'

    if (isGet && inFlightRequests.has(url)) {
      return inFlightRequests.get(url)!
    }

    const promise = (async (): Promise<{ data: unknown }> => {
      const headers: Record<string, string> = { ...config.headers }

      if (config.attachToken) {
        const user = await userManager.getUser()
        if (user?.access_token) {
          headers['Authorization'] = `Bearer ${user.access_token}`
        }
      }

      const serializableBody = isPlainObject(config.data)
      if (serializableBody && !headers['Content-Type']) {
        headers['Content-Type'] = 'application/json'
      }

      const response = await fetch(url, {
        method: config.method || 'GET',
        headers,
        body: config.data ? (serializableBody ? JSON.stringify(config.data) : (config.data as BodyInit)) : undefined,
        signal: config.signal,
      })

      if (!response.ok) {
        const errorText = await response.text().catch(() => '')
        let body: unknown = errorText
        try {
          body = JSON.parse(errorText) as unknown
        } catch {}
        throw new HttpError(response.status, response.statusText, body)
      }

      const text = await response.text()
      const contentType = response.headers.get('content-type')
      let data: unknown = text
      if (contentType?.includes('application/json') && text) {
        try {
          data = JSON.parse(text) as unknown
        } catch (e) {
          console.warn('Failed to parse JSON response body:', e)
        }
      }

      return { data }
    })()

    if (isGet) {
      inFlightRequests.set(url, promise)
      void promise.finally(() => inFlightRequests.delete(url))
    }

    return promise
  },
}
