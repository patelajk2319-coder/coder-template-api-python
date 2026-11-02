# coder-template-api-python

Coder workspace template for [api-python](https://github.com/patelajk2319-coder/api-python) — Docker-in-Docker on Coder.

## Prerequisites

- A reachable Coder URL, admin credentials, a `coderd` API token
- GitHub external auth configured on the control plane

```bash
brew install terraform coder go-task shellcheck
```

## Quick Start

```bash
git clone https://github.com/patelajk2319-coder/coder-template-api-python.git
cd coder-template-api-python
cp .env.example .env    # fill in values — each one is commented
task up                 # validate, then push the template
task workspace           # provision a workspace (first time needs GitHub auth in browser)
task logs                 # tail startup logs
```

## Local API Access

```bash
coder port-forward <workspace-name> --tcp 8000:8000
```

## Commands

| Task | Description |
|---|---|
| `task up` | Validate, then push the template |
| `task template` | Push/update the template, versioned from `VERSION` |
| `task workspace` | Provision a workspace (`NAME=<name>`) |
| `task logs` | Stream startup logs from the active workspace |
| `task validate` | `terraform fmt`/`validate` + shellcheck |
| `task release` | Tag and push `VERSION` as a git release |
