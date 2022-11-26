[![Foundry][foundry-badge]][foundry]

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

# Safe Recovery Module

A Safe module to recover a lost safe.

## How does it work?

Using Safe transactions trusted addresses can be set as delegates and a recover period in seconds can be set.
Any of the delegates' addresses can start the recovery process and finally recover the safe after the recover period has passed.
During the recover period the recovery process can be stopped at any time using Safe transactions

## Development status

Currently the module is still WIP.
It is not deployed on any networks yet.

### Todos:

- [] Deploy on görli
- [] Add more tests
- [] Refactor contract
