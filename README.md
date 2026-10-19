# Orbit Hiring Prototype

Orbit is an interactive, front-end-only prototype for a hiring platform. It demonstrates job discovery, candidate search, chat, interview scheduling, business verification, and a platform admin dashboard.

## Try it locally

Open `outputs/orbit-hiring-prototype.html` in a modern browser.

## Publish a public demo with GitHub Pages

1. Create a GitHub repository. For GitHub Free, the repository must be public to use Pages.
2. Push this repository to GitHub.
3. Open **Settings → Pages**.
4. Under **Build and deployment**, choose **Deploy from a branch**, select `main` and `/ (root)`, then save.
5. Wait for the Pages deployment and open the site URL shown in Settings → Pages.

The root `index.html` forwards visitors to the prototype page under `outputs/`.

## Prototype limitations

- Accounts, chat, job applications, interviews, moderation and verification are simulated in the visitor's browser. They are not shared between visitors and are not secure production features.
- Business license and CV files are stored locally in the browser for demonstration only. Do not upload real personal documents to this prototype.
- `supabase/` contains an initial backend schema draft. It has not been applied to or validated against a Supabase project.

## Backend foundation

See [`supabase/README.md`](supabase/README.md) for the planned Supabase data model and access-control rollout. The SQL is a development starting point, not a production deployment.
