# Dependency Checklist

## Before

- [ ] Check if the functionality already exists in the project or its current dependencies
- [ ] Check if a standard library solution exists (don't add a package for what the language provides)
- [ ] Verify the package name is correct — check the official docs or registry page
- [ ] Check package maintenance: last publish date, open issues count, download count
- [ ] Check license compatibility with the project

## During

- [ ] Install the package using the project's package manager (bun/npm/pnpm/yarn, pip/uv, cargo)
- [ ] Pin to a specific version range appropriate for the project
- [ ] Update the lock file (it should happen automatically, but verify)
- [ ] If the package needs configuration, add it following existing config patterns
- [ ] If the package needs environment variables, document them

## After

- [ ] Verify the lock file was updated (package-lock.json, bun.lockb, yarn.lock, etc.)
- [ ] Run the build to verify no conflicts with existing dependencies
- [ ] Check for peer dependency warnings
- [ ] If removing a dependency: grep for all imports/requires to ensure nothing still uses it
- [ ] If upgrading: check the changelog for breaking changes and verify all consumers

## Red Flags

| Pattern | Problem |
|---|---|
| Adding a package for a 5-line utility function | Unnecessary dependency |
| Package with no updates in 2+ years | Potentially unmaintained |
| Package name slightly different from the popular one | Possible typosquat |
| Importing without installing first | Runtime crash |
| Upgrading a major version without checking changelog | Breaking changes |
| Multiple packages solving the same problem | Dependency bloat |
| Removing a package without grep-checking imports | Broken imports |
