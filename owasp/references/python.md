# Python — signatures & fixes

Django / Flask / FastAPI, SQLAlchemy/Django ORM, requests/httpx. Triage `scan.sh` hits here.

## A03 Injection — SQL
- **Look for:** f-strings/`%`/`+`/`.format()` inside `cursor.execute()`, `.raw()`, `.extra()`,
  `text()` with interpolation, `RawSQL`.
- **Fix:** parameterize.
  ```python
  # BAD
  cursor.execute(f"SELECT * FROM users WHERE email = '{email}'")
  # GOOD
  cursor.execute("SELECT * FROM users WHERE email = %s", [email])
  # SQLAlchemy Core
  conn.execute(text("SELECT * FROM users WHERE email = :email"), {"email": email})
  # Django ORM: prefer the ORM; .raw() must use params=[...]
  User.objects.raw("SELECT * FROM users WHERE email = %s", [email])
  ```

## A03 Injection — Command
- **Look for:** `os.system`, `os.popen`, `subprocess.*(..., shell=True)` with user input.
- **Fix:** `shell=False` (default) and pass an args list; avoid the shell.
  ```python
  # BAD
  subprocess.run(f"convert {name} out.png", shell=True)
  # GOOD
  subprocess.run(["convert", name, "out.png"])   # no shell
  ```

## A03 Injection — eval/exec
- **Look for:** `eval(`, `exec(`, `__import__(`, `pickle` as a parser (see deserialization).
- **Fix:** remove. Use `ast.literal_eval` for literals; `json` for data; an allowlist for dynamic dispatch.

## 17 Insecure deserialization
- **Look for:** `pickle.load/loads`, `dill`, `shelve`, `jsonpickle`, `yaml.load(x)` without
  `Loader=SafeLoader`.
- **Fix:**
  ```python
  yaml.safe_load(data)                 # not yaml.load(data)
  # never unpickle untrusted bytes — use JSON + a Pydantic/marshmallow schema
  ```

## A03/12 XSS & SSTI (templates)
- **Look for:** `render_template_string(user_input)`, `Template(...).render()` with user data,
  `| safe` in Jinja, `mark_safe()`/`format_html` misuse, `{% autoescape off %}`,
  `mark_safe` on user content.
- **Fix:** keep autoescaping on; never build templates from user input; sanitize rich HTML with
  `bleach`/`nh3`. Django templates autoescape by default — do not bypass with `|safe` on user data.

## A01/14 Path traversal
- **Look for:** `open()`, `os.path.join(base, user)`, `send_file`, `send_from_directory` with
  request data, archive extraction (`zipfile`/`tarfile`) without member checks (zip-slip).
- **Fix:** resolve and confine; reject results outside the base dir.
  ```python
  base = Path("/var/uploads").resolve()
  target = (base / name).resolve()
  if not target.is_relative_to(base):   # py3.9+
      raise ValueError("path traversal")
  ```
  For archives, validate each member path before extracting.

## A10 SSRF
- **Look for:** `requests`/`httpx`/`urllib.urlopen`/`aiohttp` with a user-supplied URL.
- **Fix:** allowlist hosts; resolve and block private/link-local/loopback ranges; disable
  redirects (`allow_redirects=False`) or re-validate hops; block `169.254.169.254`. Consider a
  vetted egress proxy.

## A02 Crypto / randomness
- **Look for:** `hashlib.md5/sha1` for passwords, `DES`/`ARC4`, `random.*` for tokens/OTPs/secrets.
- **Fix:** passwords → `argon2-cffi` or `bcrypt` (or Django's `make_password`); tokens →
  `secrets.token_urlsafe(32)`; symmetric → `cryptography` AES-GCM with KMS-managed keys.

## XXE (XML)
- **Look for:** `lxml.etree.parse`, `xml.etree`, `xml.dom.minidom`, `xmlrpc` on untrusted XML.
- **Fix:** use `defusedxml` (`from defusedxml.ElementTree import parse`); disable external entities
  and DTDs.

## A05 Misconfiguration
- **Django:** `DEBUG = True` in prod, `ALLOWED_HOSTS = ['*']`, missing `SECURE_*` settings
  (`SECURE_SSL_REDIRECT`, `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`, `SECURE_HSTS_SECONDS`),
  `SECRET_KEY` hardcoded. Fix each; load secrets from env.
- **CORS:** `CORS_ORIGIN_ALLOW_ALL = True` / `allow_origins=["*"]` in FastAPI with credentials →
  explicit allowlist.
- **TLS:** `verify=False` / `ssl._create_unverified_context()` / `CERT_NONE` → never against prod.

## 11 CSRF
- **Look for:** `@csrf_exempt`, `WTF_CSRF_ENABLED = False`, disabled middleware.
- **Fix:** keep Django/Flask-WTF CSRF protection on for cookie-session forms; only exempt true
  stateless token APIs and document why.

## A04/13 Mass assignment
- **Look for:** DRF `fields = '__all__'`, `Model(**request.data)`, Pydantic models without field
  restriction accepting privileged fields.
- **Fix:** explicit serializer `fields`/`read_only_fields`; Pydantic models with only client-settable
  fields; never let the client set `is_staff`, `is_superuser`, `role`, `kyc_status`.

## A06 Dependencies
- Run `pip-audit` or `safety check`; report high/critical CVEs with fix versions.
