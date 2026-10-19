# Orbit backend foundation (first pass)

The product currently lives in `outputs/orbit-hiring-prototype.html`; it has no application server or database. This folder starts the production data model with a Supabase/Postgres migration and strict row-level access policies.

## Suggested rollout

1. Create a Supabase project in the region that best fits the first launch market.
2. Apply `migrations/0001_core_schema.sql` in a disposable development project and resolve any migration diagnostics before production.
3. Create the private `private-documents` Storage bucket (public access disabled).
4. Add an Auth signup flow that creates `profiles` and assigns `job_seeker` or `employer` through a trusted server-side workflow. Never let clients assign `platform_admin` or change roles.
5. Build a server/API layer for company-license review, job moderation, account suspension, interview scheduling, and audit-log writes. The Supabase service-role/secret key must stay server-side.
6. Add database tests for both allowed and denied access before connecting the HTML prototype.

## Data boundaries in this schema

- Candidate and recruiter identities are Supabase Auth UUIDs, not emails or browser-wide localStorage keys.
- Candidate profiles are private by default. Employers can query only profiles that candidates made visible.
- Company credentials and resumes are metadata-linked to a private Storage object. Owners, platform admins, and authorized hiring teams get scoped access.
- Employers can publish jobs only for a verified company. Candidates can apply only to published roles at verified companies.
- Conversations and messages are readable only by their two participants (or a platform admin); a sender must equal the signed-in user.
- Platform roles are stored separately from editable profile fields. Provision admin roles from a trusted process.

This is a foundation, not yet wired into the front end. Apply it only to a development project first; production readiness requires exercising every policy against multiple accounts and verifying denied reads/writes as well as allowed ones.
