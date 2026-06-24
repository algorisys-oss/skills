# Elixir — PII sinks & fixes

Phoenix, `Logger`, Jason/Phoenix JSON views, Ecto, Sentry. Triage each `scan.sh` hit here.
Format: **what to look for → why → fix**.

## P-LOG Logs & error trackers
- **Look for:** `Logger.info("... #{inspect(user)}")`, logging `conn.params`/a changeset/struct,
  `inspect/1` of a schema with PII; Sentry capturing PII.
- **Fix:** redact via `Logger` filters and a custom `Inspect` impl; never `inspect` a PII struct raw.
  ```elixir
  # Hide sensitive fields from inspect/logs
  @derive {Inspect, except: [:card_number, :cvv, :aadhaar, :account_number]}
  schema "cards" do
    field :card_number, :string
    field :cvv, :string
  end
  # config: filter params/metadata
  config :phoenix, :filter_parameters, ["card_number", "cvv", "aadhaar", "password", "account_number"]
  config :logger, :console, metadata: [:request_id]   # not raw params
  ```

## P-RESP API responses
- **Look for:** `@derive {Jason.Encoder, ...}` over all fields, rendering the whole schema in a view,
  `json(conn, user)` of a struct with PII.
- **Fix:** explicit Phoenix view / `Jason.Encoder` `only:` allowlist of client fields; mask Tier-1.
  ```elixir
  @derive {Jason.Encoder, only: [:id, :name, :card_last4]}   # cvv/aadhaar never encoded
  ```

## P-URL URLs & query params
- **Look for:** PII/tokens in path/query params.
- **Fix:** body/header instead; never PII in a `GET` URL. (`filter_parameters` covers logged params,
  not the leak itself.)

## P-REST At rest
- **Look for:** a `:cvv`/`:pin` Ecto field (Tier 0); Tier-1 fields plaintext.
- **Fix:** remove CVV; tokenise; `Cloak.Ecto` field encryption with a KMS-managed key for Tier 1 —
  crypto detail → `owasp` A02.

## P-3P Analytics & third parties
- **Look for:** PII in analytics/external request bodies.
- **Fix:** hashed/pseudonymous id; strip PII before sending.
