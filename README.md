# Avanzderiv Pilot Edition 2.0

Avanzderiv Pilot Edition 2.0 is a free local evaluation release for testing the Avanzderiv PO → VO → RO flow on sample data and supported source files.

This repository contains the public setup assets for the Pilot Edition. The Avanzderiv engine is distributed separately as a public OCI-compatible container image.

```text
Container image: ghcr.io/avanzderiv/avanzderiv-pilot:2.0
Supported platforms: linux/amd64, linux/arm64
```

## What is included in the Pilot

- CSV and Parquet source support
- PO registration
- VO derivation
- field classification
- RO exposure
- query of exposed surfaces
- demo provisioning
- 100,000 record Pilot limit

## Repository layout

```text
avanzderiv-pilot/
  README.md
  setup.sh
  template/
    .env.template
    data/
      sample_data.csv
    metadata/
      contracts/
        public_policy_v1.json
        internal_policy_v1.json
```

The container image contains the engine. This repository contains the setup script, demo data, and public contract templates. Your runtime state is created locally on your machine.

## Runtime location

By default, on Linux the runtime is created under:

```text
/opt/avanzderiv
```

It contains:

```text
/opt/avanzderiv/
  .env
  data/
  metadata/contracts/
  state/
  warehouse/
```

You can override the runtime directory with:

```bash
export AVANZDERIV_BASE="$HOME/avanzderiv-runtime"
```

## Prerequisites

For the recommended container setup, you need one of:

- Docker
- Podman

You also need:

- Git
- Bash
- Python 3, used by `setup.sh` to generate a local secret

## Quick start with Docker

```bash
git clone https://github.com/avanzderiv/avanzderiv-pilot.git
cd avanzderiv-pilot

bash setup.sh docker-pull
export PATH="$HOME/.local/bin:$PATH"

avanzderiv status
```

Then provision the demo:

```bash
bash setup.sh demo
avanzderiv query --context public --table sample_surface_v1
```

Expected result: JSON lines containing analytical fields and a `subject_token`.

## Quick start with Podman

```bash
git clone https://github.com/avanzderiv/avanzderiv-pilot.git
cd avanzderiv-pilot

bash setup.sh podman-pull
export PATH="$HOME/.local/bin:$PATH"

avanzderiv status
```

Then provision the demo:

```bash
bash setup.sh demo
avanzderiv query --context public --table sample_surface_v1
```

## Offline Docker bundle mode

The setup script also supports the original bundled Docker archive mode:

```bash
bash setup.sh docker
```

This mode expects a local `dist/` directory containing the bundled image archive.

## Native Linux mode

Native Linux install is supported only when the distribution includes the native binary under `dist/`.

```bash
bash setup.sh native
```

or:

```bash
bash setup.sh
```

For the public GitHub setup repository, the recommended path is `docker-pull` or `podman-pull`.

## Demo flow

The demo command:

```bash
bash setup.sh demo
```

performs the following steps:

1. registers the bundled sample CSV as a Physical Object (PO);
2. classifies `rcu_id` as `SUBJECT.PERSON.PRIMARY`;
3. classifies `birth_year` as `ID.INDIRECT`;
4. derives a Virtual Object (VO) using the `identity` function;
5. exposes a Runtime/Release Object (RO) under the `public` context;
6. creates the queryable table `sample_surface_v1`.

Run:

```bash
avanzderiv query --context public --table sample_surface_v1
```

## Available CLI commands

After setup, run:

```bash
avanzderiv --help
```

The Pilot CLI includes:

```text
init
register
derive
classify
expose
query
revoke
materialize
show
catalog
describe
status
reset
backup
restore
```

## Configuration

The setup script supports:

```bash
AVANZDERIV_BASE=/custom/runtime/path
AVANZDERIV_IMAGE=ghcr.io/avanzderiv/avanzderiv-pilot:2.0
```

Example:

```bash
export AVANZDERIV_BASE="$HOME/avanzderiv-runtime"
bash setup.sh docker-pull
```

## Secrets and local state

The setup script creates `.env` locally from `template/.env.template` and generates `AVANZDERIV_SECRET_HEX` on the local machine.

Do not commit the generated `.env`, runtime state, warehouse files, SQLite files, or DuckDB files.

Recommended `.gitignore` entries:

```gitignore
.env
state/
warehouse/
*.sqlite
*.duckdb
*.db
*.log
dist/
*.tgz
.template.tar
__pycache__/
```

## Pilot boundaries

The Pilot Edition is an evaluation release. It is limited to 100,000 records and supports CSV/Parquet source processing.

It does not include Basic, Enterprise, GUI, Subject360, or production support features.

## Troubleshooting

### `avanzderiv: command not found`

Add the local bin directory to your shell path:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

To make it permanent, add the same line to your shell profile.

### Docker daemon is not running

Start Docker and rerun:

```bash
bash setup.sh docker-pull
```

### Podman is not installed

Install Podman or use Docker mode:

```bash
bash setup.sh docker-pull
```

### Template not found

The setup script expects either:

```text
template/
```

or:

```text
.template.tar
```

Make sure you run setup from the repository root.

## License

Avanzderiv Pilot Edition 2.0 is provided for evaluation. See `LICENSE` for usage terms.

