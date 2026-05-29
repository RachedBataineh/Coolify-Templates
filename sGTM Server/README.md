# sGTM Server

Docker image: `gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable`

You need to create **two** resources in the same Coolify project using the same Docker image — one for **production** and one for **preview**.

Set the exposed port to **8080** on both.

## Environment Presets

- `.env_preview` — use for the preview resource
- `.env_production` — use for the production resource

Set `PREVIEW_SERVER_URL` in production to enable dual-container (preview + production) mode.
