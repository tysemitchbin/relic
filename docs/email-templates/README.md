# Auth email templates

Source of truth for the Supabase Auth emails. Supabase only stores these in the
dashboard, so edit them here and paste them back in.

## Where they go

**Supabase → Authentication → Emails → Templates**

| File | Template | Suggested subject |
|---|---|---|
| `confirm-signup.html` | Confirm signup | `Confirm your Relic email` |
| `magic-link.html` | Magic Link | `Your Relic sign-in link` |
| `reset-password.html` | Reset Password | `Reset your Relic password` |

Paste the whole file into the template body. Set the subject line in the field
above it.

## Variables used

- `{{ .ConfirmationURL }}` — the verify link (button + plaintext fallback)
- `{{ .Email }}` — recipient address, shown in the body

## Sender

**Authentication → Emails → SMTP Settings**

- Sender email: `hello@myrelicmap.com` (not `noreply@` — it's a mild spam signal
  and kills replies-as-engagement)
- Sender name: `Relic`

## Deliverability notes

SPF / DKIM / DMARC all pass (checked 2026-09-02). Spam placement is down to:

1. **New-domain reputation** — `myrelicmap.com` has no sending history. Resolves
   over ~1–2 weeks of real sending; mark early ones "Not spam".
2. **Link-domain mismatch** — the button points at `*.supabase.co`, not
   `myrelicmap.com`. Fix with the Supabase **Custom Domain** add-on so verify
   links become `auth.myrelicmap.com`. This is the single biggest lever.

Test changes at https://www.mail-tester.com (trigger one real reset to the
address it gives you).
