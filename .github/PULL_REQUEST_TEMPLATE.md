## Change

Describe the schema, deployment or accelerator change.

## Validation

- [ ] Local accelerator validation passes.
- [ ] PR runs only on GitHub-hosted runners, with no Azure deployment.
- [ ] Possible data loss and existing-database compatibility reviewed.
- [ ] Directly related setup/operations documentation updated.

## Release

For production promotion, use the exact artifact from a successful main-branch
dev deployment. Do not substitute a PR build or rebuild for production.
