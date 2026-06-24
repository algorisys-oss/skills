# React / Frontend — signatures & fixes

Client-side risk is mostly XSS, secret leakage into the bundle, and token storage. Remember:
**all client code and `REACT_APP_*`/`NEXT_PUBLIC_*` vars ship to the browser** — never a secret store.

## A03/12 XSS — `dangerouslySetInnerHTML`
- **Look for:** `dangerouslySetInnerHTML={{ __html: userValue }}`.
- **Fix:** render as text (default JSX escaping) when possible. If HTML is required, sanitize:
  ```jsx
  import DOMPurify from 'dompurify'
  <div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(html) }} />
  ```
  Configure an allowlist of tags/attrs; strip `on*` handlers and `javascript:` URLs.

## A03/12 XSS — DOM sinks
- **Look for:** `element.innerHTML =`, `insertAdjacentHTML`, `document.write`, direct `ref.current.innerHTML`.
- **Fix:** use `textContent`, React state, or sanitize as above.

## XSS via URLs (`href`/`src`)
- **Look for:** `<a href={userUrl}>`, `<iframe src={userUrl}>`, `window.location = userUrl`.
- **Fix:** validate the scheme — allow only `http:`/`https:`/`mailto:`; reject `javascript:`,
  `data:`, `vbscript:`. Helper:
  ```js
  const safe = (u) => /^(https?:|mailto:)/i.test(u) ? u : '#'
  ```

## 16 Open redirect (client)
- **Look for:** `navigate(searchParams.get('next'))`, `window.location = returnTo`.
- **Fix:** allow only relative same-origin paths (must start with a single `/`, not `//`).

## 18 Secrets in the bundle
- **Look for:** `REACT_APP_*SECRET/KEY/TOKEN/PASSWORD`, `NEXT_PUBLIC_*` secrets, API keys, private
  keys, hardcoded credentials in any client file.
- **Fix:** move to a backend proxy; the browser must never hold a privileged secret. Public,
  scoped keys (e.g. publishable Stripe key) are fine — confirm scope. Rotate anything exposed.

## A07 Tokens in web storage
- **Look for:** `localStorage.setItem('token'|'jwt'|...)`, `sessionStorage` for auth tokens.
- **Why:** readable by any XSS; no `HttpOnly` protection.
- **Fix:** prefer `HttpOnly`, `Secure`, `SameSite` cookies set by the backend. If tokens must live
  in JS, keep them in memory only and accept the XSS trade-off explicitly; minimize lifetime.

## `target="_blank"` reverse tabnabbing
- **Look for:** `<a target="_blank">` without `rel`.
- **Fix:** add `rel="noopener noreferrer"`. (Modern React/browsers add `noopener` by default, but
  set it explicitly for older targets.)

## A05 Frontend hardening (report as design/config findings)
- **CSP:** ship a Content-Security-Policy (ideally nonce-based) from the server; flag inline
  scripts/styles that force `unsafe-inline`.
- **SRI:** third-party `<script>`/`<link>` from a CDN should have `integrity` + `crossorigin`
  (A08 integrity).
- **No sensitive data in `localStorage`** (PII/KYC) — it persists and is XSS-readable.
- **Source maps:** do not deploy production source maps publicly if they expose internal logic.

## Framework notes
- **Next.js:** API routes are backend — apply `nodejs.md` rules there. `NEXT_PUBLIC_*` is public.
  Watch SSRF in `next/image` remote loaders and server actions handling user URLs.
- **Vue (if present):** `v-html` is the `dangerouslySetInnerHTML` equivalent — same fix.
