# SolidJS / SolidStart — signatures & fixes

Solid is a JSX framework, so the **generic frontend sinks in `react.md` also apply** here — DOM
`innerHTML =`/`insertAdjacentHTML`/`document.write`, `href={userUrl}`, `window.location =`, tokens
in `localStorage`/`sessionStorage`, `target="_blank"` tabnabbing, and CSP/SRI hardening. This file
covers what is **Solid-specific**. Read `react.md` alongside it.

## A03/12 XSS — the `innerHTML` JSX prop
- **Look for:** `<div innerHTML={userValue} />`. Solid has **no `dangerouslySetInnerHTML`** — you
  set `innerHTML` directly as a prop, so this is the Solid equivalent and is easy to miss.
- **Fix:** render as a text child (`<div>{userValue}</div>` — Solid escapes interpolated text), or
  sanitize when HTML is required:
  ```jsx
  import DOMPurify from 'dompurify'
  <div innerHTML={DOMPurify.sanitize(html)} />
  ```
- Same applies to the `html` tagged-template from `solid-js/html` — interpolating untrusted data
  injects markup.

## A03 XSS / design — `<Dynamic>` with a user-controlled component
- **Look for:** `<Dynamic component={userValue} .../>` where the tag/component name comes from input.
- **Fix:** map untrusted input through an **allowlist** of known components; never resolve a
  component (or HTML tag string) directly from user data.

## 16 Open redirect — Solid Router
- **Look for:** `const navigate = useNavigate(); navigate(searchParams.next)`, `redirect(returnTo)`
  in a server action / `cache`, `<Navigate href={userUrl} />`.
- **Fix:** allow only relative same-origin paths — must start with a single `/` (reject `//` and
  absolute URLs):
  ```js
  const safe = (p) => /^\/(?!\/)/.test(p) ? p : '/'
  ```

## 18 Secrets in the bundle — Vite `import.meta.env`
- **Look for:** `import.meta.env.VITE_*SECRET/KEY/TOKEN/PASSWORD`. **Vite exposes every `VITE_`-
  prefixed var to the client bundle** — the Solid analogue of `REACT_APP_*`/`NEXT_PUBLIC_*`.
- **Fix:** server-only secrets must **not** carry the `VITE_` prefix; read them via `process.env`
  inside a server function / API route, never in client code. Public scoped keys (e.g. a
  publishable key) are fine — confirm scope. Rotate anything that shipped.

## SolidStart server functions & API routes are BACKEND
- **Look for:** `"use server"` directives, `action(...)`, `query(...)`/`cache(...)`, and files under
  `src/routes/**` that export `GET`/`POST` (API routes).
- **Why:** these compile to public HTTP endpoints. Their arguments are **untrusted input**, and they
  run with server privileges.
- **Apply `nodejs.md` rules** to all server-function bodies: validate/parse args (don't trust the
  client), enforce **authentication AND authorization** (A01 — a server function is not protected
  just because the UI hid the button), watch SQL/command injection, SSRF, and path traversal on any
  argument that reaches a sink.

## Reactivity note
- Solid's text interpolation `{value}` escapes by default (good). The danger is exclusively the
  explicit `innerHTML`/`html`-template/`Dynamic` escape hatches above and the shared DOM sinks in
  `react.md`.
