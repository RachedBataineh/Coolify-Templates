# Coolify Templates

Docker Compose templates for [Coolify](https://coolify.io/), configured and working.

> I made these for the apps I use because the existing templates out there were either broken, misconfigured, or unavailable. Each one has proper healthchecks, Coolify service variables, and sensible defaults out of the box.

Each folder contains a template for a specific app. Check the individual folders for details.

## How to Use

1. **Pick a template** — browse the folders.
2. **Copy the `docker-compose.yaml`** into a new Coolify **Docker Compose** project (or use the "Import from URL" option).
3. **Set your domains** in the Coolify UI under each service's **Domains** field.
4. **Configure environment variables** — each template uses Coolify's built-in service variables (`SERVICE_PASSWORD_*`, `SERVICE_USER_*`, `SERVICE_HEX_*`, `SERVICE_URL_*`, etc.) which are auto-generated. Any additional required variables are noted in the template's folder.
5. **Deploy.**

## Contributing

Found a bug or have an improvement? PRs and issues are welcome.

## License

The templates in this repo are MIT licensed. Each application has its own license — check the respective project.