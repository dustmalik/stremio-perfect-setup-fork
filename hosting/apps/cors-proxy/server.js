'use strict';

const http = require('node:http');
const { Readable } = require('node:stream');

const host = process.env.HOST || '0.0.0.0';
const port = Number(process.env.PORT || 8080);
const corsMaxAge = Number(process.env.CORS_MAX_AGE || 600);
const allowedMethods = 'GET,HEAD,POST,PUT,PATCH,DELETE,OPTIONS';
const hopByHopHeaders = new Set([
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade'
]);

function parseCsv(value) {
  return (value || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

const allowedOrigins = parseCsv(process.env.ALLOWED_ORIGINS).map((origin) => origin.toLowerCase());
const allowedTargetHosts = parseCsv(process.env.ALLOWED_TARGET_HOSTS).map((hostName) => hostName.toLowerCase());
const requireHeaders = parseCsv(process.env.REQUIRE_HEADERS);

function isHostPatternMatch(hostName, allowedHost) {
  if (allowedHost.startsWith('*.')) {
    const suffix = allowedHost.slice(1);
    return hostName.endsWith(suffix);
  }

  if (allowedHost.startsWith('.')) {
    return hostName.endsWith(allowedHost);
  }

  return hostName === allowedHost;
}

function parseOriginPattern(originPattern) {
  const match = originPattern.match(/^([a-z][a-z0-9+.-]*):\/\/([^/]+)$/i);
  if (!match) {
    return null;
  }

  const [, protocol, hostPort] = match;
  const lastColonIndex = hostPort.lastIndexOf(':');
  const hasPort = lastColonIndex !== -1 && !hostPort.endsWith(']');
  const hostName = hasPort ? hostPort.slice(0, lastColonIndex) : hostPort;
  const port = hasPort ? hostPort.slice(lastColonIndex + 1) : '';

  return {
    protocol: protocol.toLowerCase(),
    hostName: hostName.toLowerCase(),
    port
  };
}

function isOriginAllowed(origin) {
  if (!origin) {
    return false;
  }

  let parsedOrigin;
  try {
    parsedOrigin = new URL(origin.toLowerCase());
  } catch {
    return false;
  }

  return allowedOrigins.some((allowedOrigin) => {
    if (!allowedOrigin.includes('*') && !allowedOrigin.includes('://.')) {
      return parsedOrigin.origin === allowedOrigin;
    }

    const parsedPattern = parseOriginPattern(allowedOrigin);
    if (!parsedPattern) {
      return false;
    }

    return parsedOrigin.protocol === `${parsedPattern.protocol}:`
      && parsedOrigin.port === parsedPattern.port
      && isHostPatternMatch(parsedOrigin.hostname, parsedPattern.hostName);
  });
}

function isTargetHostAllowed(hostName) {
  if (!hostName) {
    return false;
  }

  const normalizedHost = hostName.toLowerCase();

  return allowedTargetHosts.some((allowedHost) => isHostPatternMatch(normalizedHost, allowedHost));
}

function appendVary(headers, value) {
  const current = headers.Vary || headers.vary;
  if (!current) {
    headers.Vary = value;
    return;
  }

  headers.Vary = `${current}, ${value}`;
}

function setCorsHeaders(res, origin, requestedHeaders) {
  res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Access-Control-Allow-Methods', allowedMethods);
  res.setHeader('Access-Control-Allow-Headers', requestedHeaders || 'Authorization, Content-Type, X-Requested-With');
  res.setHeader('Access-Control-Max-Age', String(corsMaxAge));
  res.setHeader('Vary', 'Origin, Access-Control-Request-Headers');
}

function writeJson(res, statusCode, payload, origin) {
  if (origin && isOriginAllowed(origin)) {
    setCorsHeaders(res, origin);
  }

  res.writeHead(statusCode, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload));
}

function getTargetUrl(req) {
  const trimmedUrl = req.url.startsWith('/') ? req.url.slice(1) : req.url;
  if (!trimmedUrl) {
    return null;
  }

  try {
    return new URL(trimmedUrl);
  } catch {
    return null;
  }
}

function hasRequiredHeader(req) {
  if (requireHeaders.length === 0) {
    return true;
  }

  return requireHeaders.some((headerName) => req.headers[headerName.toLowerCase()]);
}

function buildUpstreamHeaders(req, targetUrl) {
  const headers = new Headers();

  Object.entries(req.headers).forEach(([headerName, headerValue]) => {
    if (headerValue == null || hopByHopHeaders.has(headerName)) {
      return;
    }

    if (['host', 'origin', 'referer', 'cookie', 'cookie2'].includes(headerName)) {
      return;
    }

    if (Array.isArray(headerValue)) {
      headerValue.forEach((value) => headers.append(headerName, value));
      return;
    }

    headers.set(headerName, headerValue);
  });

  headers.set('host', targetUrl.host);
  return headers;
}

const server = http.createServer(async (req, res) => {
  if (req.url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true }));
    return;
  }

  const origin = req.headers.origin;
  if (!hasRequiredHeader(req)) {
    writeJson(res, 403, { error: `Missing required header. Expected one of: ${requireHeaders.join(', ')}` }, origin);
    return;
  }

  if (!isOriginAllowed(origin)) {
    writeJson(res, 403, { error: 'Origin not allowed', allowedOrigins }, origin);
    return;
  }

  if (req.method === 'OPTIONS') {
    setCorsHeaders(res, origin, req.headers['access-control-request-headers']);
    res.writeHead(204);
    res.end();
    return;
  }

  const targetUrl = getTargetUrl(req);
  if (!targetUrl) {
    writeJson(res, 400, {
      error: 'Invalid target URL',
      usage: 'Request /https://api.example.com/path?query=value'
    }, origin);
    return;
  }

  if (!['http:', 'https:'].includes(targetUrl.protocol)) {
    writeJson(res, 403, { error: 'Only http and https targets are allowed' }, origin);
    return;
  }

  if (!isTargetHostAllowed(targetUrl.hostname)) {
    writeJson(res, 403, { error: 'Target host not allowed', targetHost: targetUrl.hostname }, origin);
    return;
  }

  try {
    const response = await fetch(targetUrl, {
      method: req.method,
      headers: buildUpstreamHeaders(req, targetUrl),
      body: ['GET', 'HEAD'].includes(req.method) ? undefined : Readable.toWeb(req),
      duplex: ['GET', 'HEAD'].includes(req.method) ? undefined : 'half',
      redirect: 'follow'
    });

    const responseHeaders = {};
    response.headers.forEach((value, headerName) => {
      if (hopByHopHeaders.has(headerName)) {
        return;
      }

      if (headerName.startsWith('access-control-')) {
        return;
      }

      responseHeaders[headerName] = value;
    });

    appendVary(responseHeaders, 'Origin');
    setCorsHeaders(res, origin, req.headers['access-control-request-headers']);
    if (Object.keys(responseHeaders).length > 0) {
      res.setHeader('Access-Control-Expose-Headers', Object.keys(responseHeaders).join(', '));
    }
    Object.entries(responseHeaders).forEach(([headerName, headerValue]) => {
      res.setHeader(headerName, headerValue);
    });

    res.writeHead(response.status);

    if (!response.body) {
      res.end();
      return;
    }

    Readable.fromWeb(response.body).pipe(res);
  } catch (error) {
    writeJson(res, 502, { error: 'Upstream request failed', detail: error.message }, origin);
  }
});

server.listen(port, host, () => {
  console.log(`Restricted CORS proxy listening on ${host}:${port}`);
});
