# License inventory

The Phase 1 recursive inventory is recorded in `DEPENDENCIES.md` and
`../Docs/Audits/VITA3K_SUBMODULES.tsv`. It includes the pinned source identity,
observed license evidence and unresolved review work. Before a binary release,
it must be promoted to a complete SBOM covering every direct and transitive
component, source URL and commit/version, SPDX expression, linkage type,
notice/source requirements and iOS distribution notes.

Vita3K's root project declares GPLv2. No release may be produced until the
combined-work and third-party license review in `ROADMAP.txt` is complete.
