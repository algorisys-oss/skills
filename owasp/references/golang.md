# Go (Golang) — signatures & fixes

net/http, gin/echo/fiber/chi/gorilla, `database/sql`/sqlx/gorm, `html/template`. Triage `scan.sh`
hits here. Run `govulncheck ./...` (official, call-graph aware) and `gosec ./...` (SAST) as second
opinions — `govulncheck` is the A06 dependency auditor for Go.

## A03 Injection — SQL
- **Look for:** `fmt.Sprintf` into `Query`/`QueryRow`/`Exec`/`QueryContext`, string `+`
  concatenation into a query, gorm `.Where(fmt.Sprintf(...))` / `.Raw(fmt.Sprintf(...))`.
- **Fix:** use placeholders (`$1`/`?` per driver); the driver parameterizes.
  ```go
  // BAD
  db.Query(fmt.Sprintf("SELECT * FROM users WHERE email = '%s'", email))
  // GOOD
  db.Query("SELECT * FROM users WHERE email = $1", email)   // pq / pgx
  db.Query("SELECT * FROM users WHERE email = ?", email)    // mysql
  // gorm
  db.Where("email = ?", email).First(&u)                    // GOOD
  db.Where(fmt.Sprintf("email = '%s'", email))              // BAD
  ```

## A03 Injection — Command
- **Look for:** `exec.Command("sh", "-c", userInput)`, `exec.Command("bash", ...)`,
  `exec.CommandContext` with a shell, building the arg string from request data.
- **Fix:** invoke the binary directly with separate args; never go through a shell.
  ```go
  // BAD
  exec.Command("sh", "-c", "convert "+name+" out.png")
  // GOOD
  exec.Command("convert", name, "out.png")   // no shell, args are not re-parsed
  ```

## A03/12 XSS & templates
- **Look for:** importing `text/template` to render HTML (no auto-escaping), wrapping user data in
  `template.HTML(x)` / `template.JS` / `template.URL` / `template.HTMLAttr` (these *bypass*
  escaping), writing raw user bytes to the `http.ResponseWriter`.
- **Fix:** use `html/template` (context-aware auto-escaping) for any HTML response; never wrap
  untrusted data in `template.HTML` et al. Set `Content-Type` explicitly. For user-supplied rich
  HTML, sanitize with `bluemonday` first, then mark safe.

## A01/14 Path traversal
- **Look for:** `os.Open`/`os.ReadFile`/`os.Create`/`os.Remove`/`http.ServeFile` with request data;
  `filepath.Join(base, userInput)`; archive extraction without member validation (zip-slip).
- **Fix:** clean and confine to a base dir; reject results outside it.
  ```go
  base, _ := filepath.Abs("/var/uploads")
  target := filepath.Join(base, filepath.Clean("/"+name))   // strip leading ../
  if !strings.HasPrefix(target, base+string(os.PathSeparator)) {
      return errors.New("path traversal")
  }
  ```
  Prefer `http.FileServer(http.Dir(base))` over hand-rolled `http.ServeFile` with raw `r.URL.Path`.

## A10 SSRF
- **Look for:** `http.Get`/`http.Post`/`http.Head`/`http.NewRequest` with a user-supplied URL
  (webhooks, fetch-by-URL, KYC provider callbacks).
- **Fix:** allowlist hosts; use a custom `http.Transport`/`DialContext` (or `Control` hook) that
  rejects private/link-local/loopback IPs after resolution; cap redirects via
  `Client.CheckRedirect`; block `169.254.169.254`.

## 16 Open redirect
- **Look for:** `http.Redirect(w, r, r.URL.Query().Get("next"), ...)`, redirect target from form/query.
- **Fix:** allow only relative same-origin paths (must start with a single `/`, not `//`) or an
  allowlist of absolute URLs.

## A02 Crypto / randomness
- **Look for:** `crypto/md5`, `crypto/sha1` for passwords, `crypto/des`, `crypto/rc4`,
  **`math/rand`** for tokens/IDs/OTPs (predictable), hardcoded keys.
- **Fix:** tokens/keys → `crypto/rand` (`rand.Read`); passwords → `golang.org/x/crypto/bcrypt` or
  `argon2`; symmetric → `crypto/aes` with GCM and a KMS-managed key. Never `math/rand` for secrets.

## A07 Auth — JWT
- **Look for:** `jwt.Parse` whose keyfunc does not check `token.Method` (alg confusion),
  `jwt.SigningMethodNone` / `UnsafeAllowNoneSignatureType`, no expiry validation, secrets in code.
- **Fix:** in the keyfunc assert the expected method (`*jwt.SigningMethodHMAC` /
  `*jwt.SigningMethodRSA`) and reject others; validate `exp`; load secrets from env/secret-manager.

## A05 Misconfiguration
- **TLS:** `tls.Config{InsecureSkipVerify: true}` → never against production endpoints.
- **CORS:** `Access-Control-Allow-Origin: *` (especially with credentials), gin/echo
  `AllowAllOrigins: true` / `AllowOrigins: ["*"]` → explicit allowlist.
- **Cookies:** set `Secure: true, HttpOnly: true, SameSite: http.SameSiteLaxMode` on
  `http.Cookie`.
- **Headers:** add security headers (CSP, HSTS, X-Frame-Options) via middleware.
- **Errors:** do not send `err.Error()` / stack traces to clients in production.
- **pprof:** ensure `net/http/pprof` is not exposed on a public listener.

## A08/17 Deserialization
- **Look for:** `encoding/gob` decoding untrusted input, `yaml.Unmarshal` into `interface{}` from
  untrusted source, `xml.Unmarshal` with custom entity handling.
- **Fix:** prefer `encoding/json` into typed structs with validation; do not `gob`-decode untrusted
  bytes. Go's stdlib `encoding/xml` does not resolve external entities (XXE-safe by default) — keep
  it that way; be wary of third-party XML libs.

## A04/13 Mass assignment
- **Look for:** `c.BindJSON(&model)` / `c.ShouldBind(&model)` (gin) or `json.NewDecoder(r.Body).Decode(&model)`
  binding straight into a domain struct that has privileged fields (`IsAdmin`, `Role`, `KYCStatus`,
  `Balance`).
- **Fix:** bind into a request DTO struct containing only client-settable fields, then map allowed
  fields onto the model server-side. Do not expose privileged fields on the bound struct (or tag
  them `json:"-"`).

## A04 Insecure design
- Rate-limit auth/OTP/KYC endpoints (e.g. `golang.org/x/time/rate`, middleware) and add idempotency
  keys to onboarding/payment handlers (see race conditions in `catalog.md`).
- Concurrency: guard shared state with the `sync` package or channels; for invariant-critical
  updates use DB transactions / `SELECT ... FOR UPDATE`, not in-process locks alone.

## A06 Dependencies
- `govulncheck ./...` — reports only vulnerabilities your code actually reaches. Report findings
  with the fixed module version. `go mod tidy` and keep modules current.
