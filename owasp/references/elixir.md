# Elixir / Phoenix — signatures & fixes

Phoenix, Ecto, LiveView. Phoenix has strong secure defaults — many findings here are about
*bypassing* them. Triage `scan.sh` hits. Use `mix sobelow` (Phoenix-aware static scanner) as a
second opinion and cross-check its findings against this list.

## A03 Injection — SQL (Ecto)
- **Look for:** interpolation `#{...}` inside `fragment("...")`, `Repo.query("..." <> x)`,
  `Ecto.Adapters.SQL.query` with string building.
- **Fix:** use `?` placeholders in `fragment`, or the query DSL (parameterizes automatically).
  ```elixir
  # BAD
  from u in User, where: fragment("email = '#{email}'")
  # GOOD
  from u in User, where: u.email == ^email
  from u in User, where: fragment("lower(email) = ?", ^String.downcase(email))
  ```

## A03 Injection — Command / code eval
- **Look for:** `System.cmd` / `:os.cmd` with user data, `Code.eval_string`, `Code.eval_quoted`,
  `:erlang.binary_to_term` on input.
- **Fix:** `System.cmd` takes an args list (no shell) — keep it that way and never interpolate user
  input into the command or args derived from a shell string. Remove `Code.eval_*` on user input.

## 17 Deserialization & atom exhaustion
- **Look for:** `:erlang.binary_to_term(user_data)`, `String.to_atom(user_input)`,
  `:erlang.binary_to_atom`, `String.to_existing_atom` is safer but still check.
- **Why:** `binary_to_term` can construct arbitrary terms; unbounded atom creation exhausts the
  global atom table (DoS).
- **Fix:** never `binary_to_term` untrusted data (or pass `[:safe]` and still distrust it); use
  `String.to_existing_atom/1` against a known set, or keep values as strings.

## A03/12 XSS (EEx / HEEx / LiveView)
- **Look for:** `raw(user_content)`, `{:safe, user_content}`, `Phoenix.HTML.raw/1` on user input.
- **Why:** HEEx auto-escapes; `raw/` opts out.
- **Fix:** render as plain assigns (auto-escaped). For user-supplied rich HTML, sanitize first
  (e.g. `HtmlSanitizeEx`), then `raw/1` the sanitized output only.

## 11 CSRF
- **Look for:** removed `plug :protect_from_forgery`, or `:fetch_session`/CSRF plug missing from
  the browser pipeline.
- **Fix:** keep `protect_from_forgery` in the `:browser` pipeline; ensure forms use the CSRF token.
  API-only token pipelines are lower risk but document the decision.

## A04/13 Mass assignment (changesets)
- **Look for:** `cast(params, __schema__(:fields))`, casting all fields, casting sensitive fields
  (`:role`, `:admin`, `:kyc_status`, `:balance`) that the client should not set.
- **Fix:** `cast/3` with an explicit allowlist of permitted fields; set privileged fields in
  server code, not from `params`.
  ```elixir
  # BAD
  cast(user, params, __schema__(:fields))
  # GOOD
  cast(user, params, [:name, :email])   # role/kyc_status set elsewhere
  ```

## A01 Access control
- **Look for:** controllers/LiveViews fetching by ID without scoping to the current user/tenant
  (`Repo.get(Record, id)` with no owner check).
- **Fix:** scope every query: `from r in Record, where: r.id == ^id and r.org_id == ^current_org`.
  In LiveView, re-check authz on every `handle_event` — never trust the mounted assigns alone.

## A01/14 Path traversal
- **Look for:** `File.read/rm/open/stream` with `params`/`conn`-derived paths,
  `Plug.Upload` filename used directly.
- **Fix:** confine to a base dir; use `Path.safe_relative/1` (or validate the expanded path stays
  inside the base); generate server-side filenames for uploads.

## A10 SSRF
- **Look for:** `HTTPoison`/`Finch`/`Req`/`Tesla`/`:httpc` with a user-supplied URL.
- **Fix:** allowlist hosts; block private/link-local ranges; disable auto-redirects or re-validate.

## A02 Crypto / randomness
- **Look for:** `:crypto.hash(:md5|:sha, ...)` for passwords, `:rand.uniform` /
  `:crypto.rand_uniform` for tokens.
- **Fix:** passwords → `Bcrypt`/`Argon2`/`Pbkdf2` (comeonin family); tokens →
  `:crypto.strong_rand_bytes(32) |> Base.url_encode64()`; AES-GCM for symmetric.

## A05 Misconfiguration
- **Look for:** `force_ssl` missing in prod endpoint, session cookie without `secure`/`http_only`,
  `verify: :verify_none` in HTTP/TLS client opts, debug error pages enabled in prod,
  `secret_key_base` hardcoded.
- **Fix:** `force_ssl`, `secure: true, http_only: true, same_site: "Lax"` on session,
  `secret_key_base` from env, `code_reloader: false`/`debug_errors: false` in prod.

## A04 Insecure design
- LiveView events and channel handlers are server entry points — validate and authorize each one.
- Rate-limit auth/OTP/KYC endpoints (e.g. `Hammer`); add idempotency to onboarding state
  transitions (see race conditions in `catalog.md`).

## A06 Dependencies
- Run `mix deps.audit` (mix_audit) and `mix hex.audit`; report advisories with fix versions.
