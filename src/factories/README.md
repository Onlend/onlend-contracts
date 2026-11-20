# Factories

Deterministic (EIP-1167 clone) deployment for the protocol's pluggable contracts. Two layers, each
with a narrow job:

```
LendingAppFactory                          (one, whole-app orchestrator; inherits FactoryRegistry)
  │  deploy(modules) — routes each {cloneFactory, salt, data} to the registered Clone Factory
  │  it names, forwards raw bytes — does not decode
  ▼
Clone Factory (per Kind)                   (e.g. ComposedIRMFactory, BorrowablePoolFactory)
  │  clone(salt, bytes data) — decodes data itself
  ▼
Clone instance                             (the real, initialized contract)
```

## Layers

### LendingAppFactory

Single entry point for deploying a whole app instance. Takes a config describing every module to
deploy (`{cloneFactory, salt, data}` per module) and calls the registry's internal `_clone` once
per entry. Inherits `FactoryRegistry` directly, so there is one flat, app-wide allow-list of Clone
Factories rather than one per module family.

### FactoryRegistry

Owner-curated allow-list of Clone Factories. Provides the internal `_clone(cloneFactory, salt,
data)` used by `deploy`, and the external `predictAddress(cloneFactory, caller, salt)`, both
routing directly to the named Clone Factory address if it's registered. Does **not** decode `data`
— it forwards the raw bytes straight through, so it never needs to know a Clone Factory's field
shapes. A Clone Factory is registered via owner-gated `registerCloneFactory` and can be
de-registered via `removeCloneFactory`, freeing it for later re-registration.

### Clone Factory (per Kind) — `CloneFactory`

Scoped to exactly one contract kind. Holds that kind's `IMPLEMENTATION` address (immutable, never
upgraded) and exposes one permissionless function:

- `clone(salt, bytes data)` — deploys a minimal proxy at a deterministic address and initializes it
