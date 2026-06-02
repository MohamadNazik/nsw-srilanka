# NSW Sri Lanka Platform

[![Go Version](https://img.shields.io/badge/Go-1.25.7-blue.svg)](https://golang.org)
[![Platform](https://img.shields.io/badge/NSW-Platform-green.svg)](#)

`nsw-srilanka` is the deployer-specific application repository for the **Sri Lanka instance** of the National Single Window (NSW) Platform.

It depends on the core engine published as `github.com/OpenNSW/nsw/backend` (taskv2 branch) and wires Sri Lanka–specific service endpoints, payment gateways, and FCAU workflow configurations on top of it.

---

## Repository Layout

```
nsw-srilanka/
├── cmd/
│   └── server/
│       └── main.go                       # Entry point: loads config, builds the app, runs the HTTP server
├── internal/
│   └── bootstrap/
│       └── app.go                        # Wires DB, Temporal, taskv2, auth, storage, notifications, routes
├── configs/
│   ├── services.json                     # Remote service endpoints (gitignored)
│   ├── services.example.json             # Template for services.json
│   ├── payment_methods.json              # Payment gateway catalogue (gitignored)
│   ├── payment_methods.example.json      # Template for payment_methods.json
│   └── fcau/                             # FCAU health-certificate workflow + JSONForms (gitignored)
├── .env.example                          # Template for environment variables
├── .gitignore
├── Dockerfile
├── go.mod
└── go.sum
```

The Sri Lanka–specific FCAU workflow lives under `configs/fcau/` as a set of JSON files (workflow graph, JSONForms, render configs). The Go server itself is intentionally thin — most behaviour is configured via these JSON files and the `github.com/OpenNSW/nsw/backend` module.

---

## How to Run Locally

### 1. Prepare local config files
Copy the templates and edit each one for your environment:
```bash
cp .env.example .env
cp configs/services.example.json configs/services.json
cp configs/payment_methods.example.json configs/payment_methods.json
```
The FCAU workflow JSON tree under `configs/fcau/` is gitignored — make sure you have pulled it from your team's workflow template store before running the application.

### 2. Start the Docker Stack
The repository provides a unified `docker-compose.yml` stack that brings up all required backing services (PostgreSQL, IDP, Temporal) and runs the Go backend API container with hot-reloading and multi-repo workspace linking enabled.

To start the services:
```bash
docker compose up -d
```
This spins up:
* **`nsw-postgres`** (Port `5432`): Database populated with base tables/schemas.
* **`nsw-idp`** (Port `8090`): Thunder Identity Provider.
* **`temporal`** (Port `7233`) & **`temporal-ui`** (Port `8233`): Temporal workflow orchestration engine.
* **`nsw-backend-api`** (Port `8080`): The Go backend server running `go run ./cmd/server` inside the container in watch/reload mode.

#### 2. Start the Frontend (Trader Portal)
The Trader Portal frontend remains in the sibling `nsw` repository for now. You must run it locally from there:
```bash
cd ../nsw
./start-dev.sh
```
This runs the frontend dev server on `http://localhost:5173`, proxying backend requests to the Docker container at `localhost:8080` and auth requests to the Thunder IDP at `localhost:8090`.

#### 3. Sibling Repositories & Local Development (Modes A & B)
The backend container can be run in two modes using Go workspaces:

##### Mode A: Remote Dependencies (Default)
By default, the backend API compiles using the dependencies specified in `go.mod` (fetched from GitHub). You do not need to have the sibling repositories cloned locally.
* **How it works:** `GOWORK` defaults to `off` inside the container. The Docker volume bind mounts fallback to `.` (the current directory) to avoid mount errors on the host if sibling folders don't exist.

##### Mode B: Local Workspace Dependencies
If you are developing across multiple repositories and want local changes in sibling folders to be automatically picked up and compiled:
1. **Clone the sibling repositories** as siblings to `nsw-srilanka`:
   * `nsw`
   * `nsw-task-flow`
   * `go-temporal-workflow`
2. **Configure your `.env` file** to enable the workspace and specify the sibling paths:
   ```env
   # Enable Go Workspace compilation inside the container
   GOWORK=/src/go.work

   # Map host paths to the sibling directories
   NSW_PATH=../nsw
   NSW_TASK_FLOW_PATH=../nsw-task-flow
   GO_TEMPORAL_WORKFLOW_PATH=../go-temporal-workflow
   ```
3. **Initialize the `go.work` file** at the root of `nsw-srilanka`. Since workspace files are developer-specific and gitignored, you should generate it using:
   ```bash
   go work init . ../nsw-task-flow ../go-temporal-workflow ../nsw/backend
   ```
   This will generate a `go.work` file that references these local paths. (If you already have a `go.work` file, you can add missing directories using `go work use <directory_path>`).

To compile and apply your latest Go code changes from any of these local directories, you do not need to restart the entire database/IDP stack. You can quickly rebuild and restart just the backend API container:
```bash
docker compose up -d --force-recreate api
```
Or simply:
```bash
docker compose restart api
```
This re-runs `go run` inside the container, rebuilding and starting your backend in seconds while keeping PostgreSQL, Temporal, and the IDP running undisturbed.

---

### 4. Verify

- Health check: `curl http://localhost:8080/health` should return `{"status":"ok","service":"nsw-backend"}`.
- Logs will report DB connection, Temporal worker startup, and the FCAU workflow registrations from `configs/fcau/`.

### 5. Simulating a payment webhook (dev only)

INFO-type gateways (e.g. `govpay`) don't fire a real callback. To advance a `PENDING_PAYMENT` task manually:

```bash
curl -X POST http://localhost:8080/api/v1/payments/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "reference_number": "TNSW-XXXXXXXX",
    "session_id": "manual-test-1",
    "gateway_transaction_id": "MOCK-001",
    "status": "SUCCESS",
    "amount": "1500",
    "currency": "LKR",
    "payment_method": "govpay",
    "timestamp": "2026-01-01T00:00:00Z",
    "metadata": {}
  }'
```

REDIRECT-type gateways (e.g. `lankapay`) fire this webhook on their own.

---

## Upstream Dependency

The core engine is pulled directly from GitHub via Go modules:

```
github.com/OpenNSW/nsw/backend v0.0.0-…  // pinned to a taskv2 commit
```

To pull the latest taskv2:

```bash
go get github.com/OpenNSW/nsw/backend@taskv2
go mod tidy
```

There is **no** `replace` directive and **no** sibling clone of `OpenNSW/nsw` required to build.

> The local module path declares itself as `github.com/OpenNSW/nsw/backend/srilanka` so Go's `internal/...` visibility rule allows importing `github.com/OpenNSW/nsw/backend/internal/*`. The physical directory name (`nsw-srilanka`) is independent of the module path.

---

## Configuration Reference

| File | Purpose | Source of truth |
|------|---------|-----------------|
| `.env` | Runtime environment (DB, Temporal, CORS, auth, storage, config paths) | `.env.example` |
| `configs/services.json` | Outbound service endpoint registry (FCAU, NPQS, IRD, customs, …) | `configs/services.example.json` |
| `configs/payment_methods.json` | Payment gateway catalogue (id, type, gateway URL, instruction template) | `configs/payment_methods.example.json` |
| `configs/fcau/` | FCAU health-certificate workflow definition + JSONForms + render configs | Per-team workflow store |

Workflow execution mechanics (input/output mappings, task plugins, render projections) are documented in the upstream `github.com/OpenNSW/nsw/backend` README and the FCAU configs themselves.
