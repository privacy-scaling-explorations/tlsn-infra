## TLSNotary Deployments

This repo provides a CI/CD pipeline that automates deployment of TLSNotary backend and frontend services to Azure SGX-based virtual machines.  
Supporting infrastructure and necessary IaC components are defined in:  
https://github.com/privacy-scaling-explorations/devops/tree/azure/tlsnotary/terraform/azure

This document focuses only on the permission model and deployment structure. Azure resource setup (e.g., networking or virtual machines) is out of scope.

## Deployment Workflow

The GitHub Actions workflow for deployment is currently manually triggered and assumes all required container images are pre-built.

### Parameters

The workflow accepts the following variables:

- Resource group name
- Environment type (`prod` or `test`)
- Source branch
- Deployment target (`frontend`, `backend`, or `both`)

> Note: Deployments to production are only allowed from the `main` branch.

### Permissions

#### GitHub Runner

The runner uses MS Entra federated identity to authenticate and receives short-lived credentials associated with a Service Principal that has:

- **Reader** role on the target resource group (to query resources and locate the appropriate VMs using tags)
- **Azure Run Command** permission to execute deployment logic remotely on the VMs

#### Backend VMs

Backend VMs must have a system-assigned managed identity with read access to the Azure Key Vault. Access is granted using **RBAC-based roles** (e.g., Key Vault Reader).

## Deployment Instructions

### 1. Update Docker Compose

Add new notary services using the following pattern:

```yaml
alpha9-sgx:
  container_name: alpha9-sgx
  labels:
    - "traefik.enable=true"
    - "traefik.http.middlewares.stripalpha9-sgx.stripprefix.prefixes=/alpha9-sgx"
    - "traefik.http.routers.alpha9-sgx.middlewares=stripalpha9-sgx"
  image: ghcr.io/tlsnotary/tlsn/notary-server-sgx:v0.1.0-alpha.9
  restart: unless-stopped
  devices:
    - /dev/sgx_enclave
    - /dev/sgx_provision
  volumes:
    - /var/run/aesmd/aesm.socket:/var/run/aesmd/aesm.socket
  ports:
    - "4109:7047"
  entrypoint: [ "gramine-sgx", "notary-server" ]
```

- Each new service must define a `traefik` HTTP router and a strip-prefix middleware to route requests correctly.
- Also update the landing page in `proxy/index.html` to reflect the new service route.

### 2. Provision Secrets in Azure Key Vault

Use the `upload-secrets.sh` script located in this repo.

#### Requirements

- Tools: `yq`, `az-cli`
- The user or automation agent must have permission to write to the Azure Key Vault.

#### Directory Structure

The script expects the following structure relative to your current working directory:

```
.
├── alpha10
│   └── fixture
│       ├── auth
│       │   └── whitelist.csv
│       ├── notary
│       │   ├── notary.key
│       │   └── notary.pub
│       └── tls
│           ├── notary.crt
│           ├── notary.csr
│           ├── notary.key
│           ├── openssl.cnf
│           ├── README.md
│           ├── rootCA.crt
│           ├── rootCA.key
│           └── rootCA.srl
├── alpha6
│   └── fixture
│       └── ...
├── alpha7
│   └── fixture
│       └── ...
├── alpha9
│   └── fixture
│       └── ...
├── docker-compose.yml
├── upload-secrets.sh
```

#### Secret Naming Convention

Secrets are uploaded using the pattern:

```
<service-name>--<base64_encoded_relative_path>
```

Encoding behavior:

- Relative file paths (e.g., `fixture/tls/rootCA.key`) are encoded using `base64 --wrap=0`
- Characters are made URL-safe by:
  - Replacing `/` with `_`
  - Replacing `+` with `-`
  - Stripping any `=` padding

This ensures secret names are compliant with Azure Key Vault constraints and file system safe.

### 3. Commit Notary Configs

If your services require additional configs, include them in the repo under the `docker/` folder:

```
docker/
├── alpha10
│   └── config
│       └── config.yaml
├── alpha10-sgx
│   └── config.yaml
...
```

### 4. Trigger the Deployment Workflow

Trigger the GitHub Actions workflow manually and supply:

- The target resource group
- The environment type (prod/test)
- The source branch
- The deployment role (backend/frontend/both)

> Note: Federated identity tokens require exact subject matches.
> Example: `repo:privacy-scaling-explorations/tlsn-infra:ref:refs/heads/main` will only work for the `main` branch.No wildcards supported yet.

### 5. What Happens During Deployment

Once triggered:

1. Runner performs `az login`
2. Validates branch/environment match
3. Identifies VMs in the resource group with matching tags (`role`, `end`)
4. Executes `az vm run-command create` to:
   - For **backend**:
     - `docker compose down`
     - Clear existing directories
     - Check out correct branch
     - Use `fetch-fixtures.sh` to reconstruct fixture directory from Key Vault
     - `docker compose up`
   - For **frontend**:
     - Copy updated `index.html` to the web frontend VM

---

## Security and Storage

- Secrets are **encrypted at rest** in Azure Key Vault.
- Secrets are **not stored as plaintext** but are accessible as plaintext upon retrieval.
- Access is controlled via RBAC and scoped managed identities.
---