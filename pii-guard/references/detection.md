# pii-guard detection — field & value signatures

How to recognise PII by **field name** and by **value format**. The scanner uses simplified versions
of these; use the full forms when triaging and when writing redaction rules. India-specific formats
are called out because they are easy to misclassify.

## Disambiguation: "PAN" means two different things
- **Card PAN** — Primary Account Number, the 13–19 digit payment card number (Tier 1, PCI).
- **Income-tax PAN** — India Permanent Account Number, format `[A-Z]{5}[0-9]{4}[A-Z]` e.g.
  `ABCDE1234F` (Tier 1, DPDP). Different data, different validation. Field names `pan`/`pan_number`
  are ambiguous — check the format/context before classifying and masking.

## Field-name signatures
Match case-insensitively, with `_`/`-`/camelCase variants:
- Tier 0: `cvv`, `cvc`, `cvv2`, `cvc2`, `card_verification`, `track_data`, `track2`, `pin`, `pin_block`.
- Tier 1: `card_number`, `cardnumber`, `pan`, `account_number`, `acct_no`, `aadhaar`/`aadhar`/`uid`,
  `passport`, `voter_id`, `dl_number`, `driving_licence`, `biometric`, `fingerprint`, `face_embedding`.
- Tier 2: `name`, `first_name`/`last_name`, `dob`, `date_of_birth`, `email`, `phone`/`mobile`/`msisdn`,
  `address`, `pincode`/`zip`, `ifsc`, `vpa`/`upi`, `gstin`, `ip_address`, `device_id`.

## Value-format signatures (for detecting raw PII in code/logs/data)
- **Card PAN** — 13–19 digits, often in groups (`\b(?:\d[ -]?){13,19}\b`); validate with the **Luhn**
  checksum to cut false positives; major BIN ranges (Visa `4`, Mastercard `5[1-5]`/`2221–2720`,
  RuPay `60/65/81/82`, Amex `3[47]`).
- **Aadhaar** — 12 digits, usually `\b[2-9]\d{3}\s?\d{4}\s?\d{4}\b` (does not start 0/1); validate
  with the **Verhoeff** checksum. Treat as Tier 1; masking shows last 4 only (`XXXX-XXXX-1234`).
- **Income-tax PAN** — `\b[A-Z]{5}[0-9]{4}[A-Z]\b` (4th char encodes holder type).
- **IFSC** — `\b[A-Z]{4}0[A-Z0-9]{6}\b` (5th char is always `0`).
- **Indian mobile** — `\b(?:\+?91[\-\s]?)?[6-9]\d{9}\b`.
- **UPI VPA** — `\b[\w.\-]{2,}@[a-z]{2,}\b` (handle@psp; distinguish from email by known PSP handles).
- **GSTIN** — `\b\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d]\b`.
- **Email** — standard RFC-ish `\b[\w.+-]+@[\w-]+\.[\w.-]+\b`.
- **Passport (India)** — `\b[A-PR-WYa-pr-wy][1-9]\d\s?\d{4}[1-9]\b` (approx; confirm in context).
- **DOB** — date fields named `dob`/`date_of_birth`, or dates adjacent to identity fields.

## Reducing false positives
- A digit run that fails **Luhn** is probably not a card PAN; a 12-digit run failing **Verhoeff** is
  probably not Aadhaar. Note checksum validation when you report a value-format hit.
- `pan` as a substring appears in `panel`, `expand`, `company` — require a word boundary and check
  surrounding context.
- Test/sample numbers (e.g. `4111 1111 1111 1111`) are still worth flagging in real logs/responses
  but are expected in fixtures — weight by location.

## Using this file
When you find a field/value, classify its **tier** (catalog.md), confirm with the format/checksum
here, then trace it to a sink. For redaction, prefer matching by **field name** at the
serialiser/logger layer (deterministic) over value-regex scrubbing of free text (best-effort).
