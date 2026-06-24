# Node.js / TypeScript — signatures & fixes

Backend Express/Nest/Fastify/Koa, Prisma/Knex/TypeORM/Sequelize, Mongo. Triage each `scan.sh`
hit here. Format: **what to look for → why → fix (with safe code)**.

## A03 Injection — SQL / query builders
- **Look for:** template literals or `+` inside `.query()`, `.raw()`, `.$queryRawUnsafe()`,
  `sequelize.query(\`...${x}\`)`, Knex `.whereRaw(\`...${x}\`)`.
- **Fix:** parameterize.
  ```js
  // BAD
  db.query(`SELECT * FROM users WHERE email = '${email}'`)
  // GOOD
  db.query('SELECT * FROM users WHERE email = $1', [email])
  // Prisma: prefer the query API; if raw is required use the tagged template (auto-parameterized)
  prisma.$queryRaw`SELECT * FROM users WHERE email = ${email}`   // safe
  prisma.$queryRawUnsafe(`... ${email}`)                          // BAD
  ```

## A03 Injection — NoSQL (Mongo)
- **Look for:** `req.body`/`req.query` objects passed straight into a filter (operator injection,
  e.g. `{ "$gt": "" }`), `$where`, `mapReduce`, `$function`.
- **Fix:** cast to expected scalar types, reject objects where a string is expected; use a schema
  (Mongoose/Zod). `const email = String(req.body.email)`. Set `mongoSanitize()` middleware.

## A03 Injection — Command
- **Look for:** `exec`, `execSync`, `spawn` with a shell, concatenating request data.
- **Fix:** avoid the shell; use `execFile`/`spawn` with an args array; never interpolate input.
  ```js
  // BAD
  exec(`convert ${req.body.file} out.png`)
  // GOOD
  execFile('convert', [safePath, 'out.png'])   // no shell, args array
  ```

## A03 Injection — eval / Function
- **Look for:** `eval(`, `new Function(`, `vm.runInNewContext` on user input.
- **Fix:** remove. Parse data with `JSON.parse`; for expressions use a sandboxed evaluator with
  an allowlist, never raw `eval`.

## XSS (when rendering server-side or building HTML strings)
- **Look for:** building HTML with template strings from user data, `res.send('<div>'+x)`.
- **Fix:** context-aware encoding; use a templating engine with auto-escape; sanitize rich HTML
  with `dompurify` (server: `isomorphic-dompurify`). See `react.md` for client-side.

## A08 Prototype pollution
- **Look for:** recursive merge/`Object.assign`/`lodash.merge` of user JSON, `obj[key]=val` where
  `key` is user-controlled, `__proto__`/`constructor`/`prototype` keys.
- **Fix:** reject `__proto__`/`constructor`/`prototype` keys; use `Object.create(null)` maps,
  `Map`, or `structuredClone`; upgrade lodash; validate with a schema before merge.

## A04/13 Mass assignment
- **Look for:** `new Model(req.body)`, `Object.assign(user, req.body)`, `prisma.user.update({data: req.body})`.
- **Fix:** allowlist explicitly: `const { name, email } = req.body; update({ name, email })`, or a
  Zod schema with `.strict()`. Never let the client set `role`, `isAdmin`, `kycVerified`, `balance`.

## A01/14 Path traversal
- **Look for:** `fs.readFile`/`sendFile`/`unlink`/`createReadStream` with `req`-derived paths.
- **Fix:** resolve and confine to a base dir.
  ```js
  const base = path.resolve('/var/uploads')
  const target = path.resolve(base, path.normalize(name))
  if (!target.startsWith(base + path.sep)) throw new Error('path traversal')
  ```

## A10 SSRF
- **Look for:** `axios`/`fetch`/`got`/`http.get` with a user-supplied URL (webhooks, fetch-by-URL,
  KYC provider callbacks, link previews).
- **Fix:** allowlist hosts; resolve DNS and reject private/link-local/loopback ranges
  (`10/8`, `172.16/12`, `192.168/16`, `127/8`, `169.254/16`, `::1`, fc00::/7); disable redirects
  (`maxRedirects: 0`) or re-validate each hop; never fetch `169.254.169.254`.

## Open redirect
- **Look for:** `res.redirect(req.query.next)`.
- **Fix:** allow only relative same-origin paths or an allowlist: reject anything starting with
  `//`, `http:`, `https:` unless host is allowlisted.

## A02 Crypto / randomness
- **Look for:** `crypto.createHash('md5'|'sha1')` for passwords, `*-ecb` ciphers, `Math.random()`
  for tokens/IDs/OTPs, hardcoded key/IV.
- **Fix:** passwords → `argon2` or `bcrypt`; tokens → `crypto.randomBytes(32).toString('hex')` or
  `crypto.randomUUID()`; symmetric → AES-256-GCM with a random IV from a KMS-managed key.

## A07 Auth — JWT / sessions
- **Look for:** `jwt.decode()` used as if it verifies, `algorithms: ['none']`, no `algorithms`
  pin, secrets in code, no expiry, tokens in localStorage (see react.md).
- **Fix:** `jwt.verify(token, key, { algorithms: ['RS256'] })` with pinned algs and `expiresIn`;
  rotate secrets via env/secret-manager; short-lived access + rotating refresh; consider httpOnly
  cookie sessions over localStorage.

## A05 Misconfiguration
- **CORS:** `cors()` (reflects any origin) / `origin: '*'` with credentials → set an explicit
  origin allowlist; never `*` with `credentials: true`.
- **Cookies:** set `secure: true, httpOnly: true, sameSite: 'lax'|'strict'`.
- **Headers:** add `helmet()`; set CSP; `app.disable('x-powered-by')`.
- **TLS:** never `rejectUnauthorized: false` against production endpoints.
- **Errors:** do not send stack traces to clients in production.

## A08/17 Deserialization
- **Look for:** `node-serialize`, `funcster`, `serialize-javascript` used to *parse* untrusted data.
- **Fix:** use `JSON.parse` + schema validation; never deserialize functions from untrusted input.

## A06 Dependencies
- Run `npm audit --omit=dev` / `pnpm audit` / `yarn npm audit`; report high/critical with the fix
  version. Check for unmaintained packages.

## A04 Insecure design — rate limiting / idempotency
- Sensitive endpoints (login, OTP, KYC submit, payment) need rate limiting (`express-rate-limit`)
  and idempotency keys. Flag their absence as a design finding.
