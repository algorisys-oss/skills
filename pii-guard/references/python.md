# Python — PII sinks & fixes

Django/DRF, Flask, FastAPI; `logging`/`structlog`; DRF/Pydantic serialisers; Sentry. Triage each
`scan.sh` hit here. Format: **what to look for → why → fix**.

## P-LOG Logs & error trackers
- **Look for:** `logging.info(f"... {user.card_number}")`, `logger.debug(request.data)`, logging a
  model/`__dict__`, PII in exception messages; `sentry_sdk` capturing PII.
- **Fix:** mask before logging; central redaction.
  ```python
  # structlog processor that drops PII keys
  def scrub(_, __, event):
      for k in ("card_number","cvv","aadhaar","account_number","password","email","phone"):
          if k in event: event[k] = "[REDACTED]"
      return event
  # Sentry: send_default_pii=False, plus a before_send scrubber
  sentry_sdk.init(send_default_pii=False, before_send=scrub_event)
  ```
  Never log `request.data`/`request.POST` wholesale on a PII route.

## P-RESP API responses
- **Look for:** DRF `fields = '__all__'`, `model_to_dict(obj)`, returning a full ORM object,
  Pydantic models echoing every field.
- **Fix:** explicit serializer `fields`/Pydantic response model with only client fields; mask Tier-1.
  ```python
  class UserOut(serializers.ModelSerializer):
      card_last4 = serializers.SerializerMethodField()
      class Meta: model = User; fields = ["id","name","card_last4"]   # never '__all__'
      def get_card_last4(self, o): return o.card_number[-4:]
  ```

## P-URL URLs & query params
- **Look for:** PII/tokens in path/query (`/users/?aadhaar=`, `?token=`).
- **Fix:** move to the body or an auth header; never PII in a `GET` URL.

## P-REST At rest
- **Look for:** a `cvv`/`pin` model field (Tier 0); Tier-1 fields stored plaintext.
- **Fix:** remove CVV; tokenise card data; field-level encryption (`django-fernet-fields`/app-layer
  with a KMS key) for Tier 1 — crypto detail → `owasp` A02.

## P-3P Analytics & third parties
- **Look for:** `analytics.track(... email ...)`, PII to Segment/GA/external APIs.
- **Fix:** hashed/pseudonymous id; strip PII before sending.
