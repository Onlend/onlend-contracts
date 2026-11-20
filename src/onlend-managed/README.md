# Onlend-managed

Contracts that Onlend deploys and maintains itself, rather than the operator of a lending app. Each is a single
instance shared by every lending app, which references it by address.

## What belongs here

A contract belongs here when it is a single instance shared by every lending app, deployed by Onlend for apps to
consume rather than configure. Any roles it has are held by Onlend, though it need not have any: a contract whose
settings are fixed at deployment qualifies just the same. Deploying a contract is not enough on its own: Onlend also
deploys the factories and the implementations behind every clone, but those stay organised by function in the rest
of `src/`, since an operator decides how each instance is configured.

## Enforced or offered

Living here describes how Onlend intends a contract to be used, not what an app is restricted to on-chain. Some
contracts are enforced: the pool factories initialise every pool with the fee registry they were deployed with, so
an app cannot choose another. Others are only offered: a yield-tracking borrow rate accepts any contract implementing
`IYieldAdapter`, so an app can point at its own adapter rather than one of Onlend's.

## Dependency direction

Contracts here may import from the rest of `src/`; nothing outside this folder imports from it. The interface each
contract implements lives with the code that consumes it, e.g. `IOnlendFeeRegistry` sits in `pool/interfaces/`
next to the pools that read it. Lending apps therefore depend only on the interface, and a new implementation can be
added here without changing any code outside this folder.
