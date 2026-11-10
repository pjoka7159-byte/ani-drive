# ANI DRIVE — Full system starter

This package is the frontend foundation for the requested student/admin workflow.

## Required before real use
This is not a complete production backend by itself. To make registration, approvals, blocking and email notifications work, configure:
- Supabase project (Auth + Postgres)
- Supabase URL and anon key in `config.js`
- An Edge Function / server-side function for admin-only approval, rejection, blocking and email sending
- An email provider API key stored only as a server-side secret (never in browser code)

## Deploy
Upload the contents of this folder to the root of your GitHub `ani-drive` repository, commit, then redeploy in Vercel.

## Security
Do not put admin passwords or email-provider secrets in frontend files. Admin access must be enforced server-side using an allowlist of verified admin email addresses and role checks.
