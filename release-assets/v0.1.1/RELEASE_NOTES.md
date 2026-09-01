# Astar.DatabaseBypass v0.1.1

SPT 4.1.x exact-version release.

## Included targets

- SPT 4.1.0
- SPT 4.1.1
- SPT 4.1.2
- SPT 4.1.3

Each SPT patch version has its own package and exact SPT version metadata. Install only the ZIP matching your installed SPT version.

## Changes

- Bypasses the SPT 4.1.x database hash verification callback before database import.
- Prevents database **hash mismatch** from blocking server startup on the supported 4.1.x targets.
- Removes SPT 4.0.x build/release support from this release matrix.
- Adds exact-version build validation, package-content validation, SHA-256 manifests, and VirusTotal scan records.

## Scope

This mod bypasses database hash consistency verification only. Missing files, a missing/corrupt `checks.dat`, invalid JSON, deserialization failures, or other database/server errors are not suppressed.
