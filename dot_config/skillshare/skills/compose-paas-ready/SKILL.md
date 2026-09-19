---
name: compose-paas-ready
description: >-
  Makes a Git repository deployable on a Docker-Compose PaaS that builds
  straight from GitHub (Coolify, Dokploy, CapRover-style, and similar
  self-hosted platforms with a managed reverse proxy) while keeping every
  committed file vendor-neutral. Use when the user asks to make a repo
  "coolify compatible/ready", deployable on a compose PaaS, self-hostable from
  GitHub, or to adapt an existing docker-composeyaml so a platform proxy can
  route a domain to it.
disable-model-invocation: true
---

# Making a repo Docker-Compose-PaaS-ready

Adapt a repository so a self-hosted platform (that builds a Compose app from a
GitHub repo and fronts it with a managed reverse proxy) can deploy it in a few
clicks, **without** naming any specific platform in committed files.

## Golden rule: keep committed files vendor-neutral

Never write a platform brand name (e.g. "Coolify") into files that land in the
repo — comments, README, env docs, anything. Describe platform-specific
behavior generically:

> "Some deployment platforms use variables like this as *magic variables*: they
> detect it, generate a domain, and wire their reverse proxy to the container."

The `SERVICE_FQDN_*` / `SERVICE_URL_*` variable names themselves are fine to
keep — platforms that recognize them act on them, others ignore them.

## File extension

Name every Compose file, GitHub Actions workflow, and other YAML file `.yaml`.
Do not create or leave `.yml` files. Docker Compose loads `docker-compose.yaml`
and `docker-compose.override.yaml` the same way it loads the three-letter
names.

## Workflow

Copy this checklist and track it:

```
- [ ] 1. Assess the app (Dockerized? which port? DB/externals? single service?)
- [ ] 2. Make the base docker-composeyaml proxy-friendly
- [ ] 3. Add docker-compose.overrideyaml to preserve local host-port access
- [ ] 4. Add/refresh .env.example
- [ ] 5. Trim .dockerignore
- [ ] 6. Add a generic "Deploying on a Docker-Compose PaaS" README section
- [ ] 7. Validate both compose views
- [ ] 8. Security pass on secrets
```

### 1. Assess

- Is there a `Dockerfile` / `docker-composeyaml` already? Reuse the existing
  multi-stage build; don't rewrite a working image.
- What single internal port does the web process listen on? (call it `<PORT>`.)
- Does it need a database or other backing service? Prefer an **external**
  `DATABASE_URL`-style env var set in the platform UI. Only bundle a Postgres
  service if the user asks — mention it as an option otherwise.
- Identify the compose service name (call it `<service>`; uppercased as
  `<SERVICE>`).

### 2. Base `docker-composeyaml` (the PaaS view)

The platform loads this file alone. Make it proxy-first:

- **Remove any hardcoded `container_name`** — the platform manages naming.
- **Remove host `ports:` on the web service** — the platform proxy owns 80/443
  on the host; publishing them clashes. Use `expose:` for `<PORT>` instead.
- **Add the magic FQDN variable** so recognizing platforms auto-generate a
  domain and route the proxy to `<PORT>`. Empty value; ignored elsewhere.
- Keep `restart`, build args, tmpfs/volumes, and any image `HEALTHCHECK`.
- Feed config via `${VAR:-default}` substitution (set real values in the UI).

```yaml
services:
  <service>:
    build: { context: . }          # keep the existing build/image
    restart: unless-stopped
    environment:
      # Some deployment platforms use a variable like this as a "magic"
      # variable: they detect it, generate a domain, and wire their reverse
      # proxy (HTTPS + WebSocket upgrade) to container port <PORT>. Locally
      # it's an unused env var, so `docker compose up` is unaffected.
      SERVICE_FQDN_<SERVICE>_<PORT>: ""
      # `${VAR:?}` is Compose interpolation for "must be set and non-empty".
      # Some platforms treat this form as a required UI field and block
      # deploy while empty. Use it for credentials the stack cannot start
      # without (e.g. DATABASE_URL). Optional knobs stay `${VAR:-default}`.
      DATABASE_URL: "${DATABASE_URL:?}"
      # ...other app env as ${VAR:-default}...
      HOST: "0.0.0.0"
      PORT: "<PORT>"
    # No host `ports:` — a managed proxy owns 80/443 and reaches the container
    # over the internal network via the FQDN variable above. `expose`
    # documents the internal port for the proxy and for the local override.
    expose:
      - "<PORT>"
```

Variable forms (document, use as needed):
- `SERVICE_FQDN_<SERVICE>_<PORT>` → generate a domain, route proxy to `<PORT>`.
- `SERVICE_URL_<SERVICE>_<PORT>: /subpath` → same, mounted under a subpath.
- Reference generated values elsewhere via `${SERVICE_FQDN_<SERVICE>_<PORT>}`.
- `${VARIABLE:?}` → required (empty/unset fails compose interpolation; some
  platforms mark it required in the UI and block deploy). Use for
  `DATABASE_URL` and other credentials the stack cannot start without.
- `${VARIABLE:-default}` → optional with a fallback.

### 3. `docker-compose.overrideyaml` (local dev, PaaS-ignored)

`docker compose` and helper scripts auto-merge `docker-compose.overrideyaml`,
but a PaaS invokes compose with an explicit `-f`, which **disables** override
auto-loading — so local conveniences never leak into the deployment. Put
host-only bits here:

```yaml
# Local-development overlay. Auto-merged by `docker compose up`; ignored by a
# managed platform that loads the base docker-composeyaml with an explicit -f.
services:
  <service>:
    container_name: <service>
    ports:
      - "${APP_PORT:-<PORT>}:<PORT>"
    extra_hosts:
      - "host.docker.internal:host-gateway"   # reach a DB on the Docker host
```

### 4. `.env.example`

Create/refresh a root `.env.example` documenting every variable, split into
**Required** / **Optional**. Note that on a hosted platform these are set in
the platform UI, and locally they go in a gitignored `.env` next to
`docker-composeyaml`. Never commit a real `.env`.

### 5. `.dockerignore`

Keep the build context lean and ensure secrets/compose/docs stay out of the
image: ignore `.env`/`.env.*` (allow `*.env.example`), `docker-compose*yaml`,
helper scripts, and `README.md`.

### 6. README section

Add a generic section titled e.g. **"Deploying on a Docker-Compose PaaS"** with
steps: connect the GitHub repo as a Docker Compose resource → point at
`/docker-composeyaml` → expose on a domain (mention the magic FQDN var as the
auto path and a manual domain→`<PORT>` route as the fallback) → set required
env vars → deploy (image `HEALTHCHECK` can gate rollout). If the app is
stateless-with-external-DB, note it resumes against the same `DATABASE_URL`.

### 7. Validate

```bash
# PaaS view — expect NO container_name, NO published ports, expose only,
# and the SERVICE_FQDN_* var present:
docker compose -f docker-composeyaml config

# Local view — expect the override merged back in (container_name, published
# ${APP_PORT}:<PORT>, host.docker.internal):
DATABASE_URL=x docker compose config
```

### 8. Security pass

Confirm `.env` is gitignored (`git check-ignore .env`) and not tracked. If any
real secret (API token, DB password) surfaced in a printed compose config or
in chat, tell the user to rotate it.

## Notes

- Per the user's convention: **do not keep backward-compatibility cruft** — if
  a host `ports:` mapping or old comment no longer fits the proxy model, remove
  it rather than leaving it commented "just in case" (a short local-override
  file is the sanctioned exception).
- Don't bundle a database unless asked; default to an external `DATABASE_URL`.
