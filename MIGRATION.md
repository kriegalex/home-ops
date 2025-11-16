# Migration Summary: Cluster Template Upgrade

This document tracks the migration from the original cluster-template to a customized version with:
- **ArgoCD** instead of Flux
- **Infomaniak DNS** instead of Cloudflare
- **Tailscale** instead of Cloudflare Tunnel for VPN access
- **Gitea** instead of GitHub for Git hosting
- **Talos Linux** retained (with vanilla Kubernetes)

## Migration Status

### ✅ Completed Changes

#### 1. Configuration Schema (`cluster.sample.yaml`)
- ✅ Updated DNS/NTP defaults (removed Cloudflare-specific defaults)
- ✅ Added Gitea repository fields (`repository_url`, `repository_type`)
- ✅ Removed Cloudflare fields (`cloudflare_domain`, `cloudflare_token`, `cloudflare_gateway_addr`)
- ✅ Added Infomaniak fields (`infomaniak_api_token`)
- ✅ Added Tailscale fields (`tailscale_auth_key`, `tailscale_enabled`)
- ✅ Added DynDNS fields for external access (`dyndns_provider`, `dyndns_token`, `dyndns_hostname`)
- ✅ Renamed external gateway (`cluster_external_gateway_addr`)

#### 2. Removed Cloudflare Components
- ✅ Deleted `templates/config/kubernetes/apps/network/cloudflare-dns/`
- ✅ Deleted `templates/config/kubernetes/apps/network/cloudflare-tunnel/`
- ✅ Updated `templates/config/kubernetes/apps/network/kustomization.yaml.j2` to remove Cloudflare references
- ✅ Added conditional Tailscale operator reference

#### 3. ArgoCD Foundation
- ✅ Created `templates/config/kubernetes/apps/argocd/` directory structure
- ✅ Created ArgoCD namespace configuration
- ✅ Created ArgoCD Helm values template with:
  - SOPS integration for secret decryption
  - Gitea repository configuration
  - ServiceMonitor enablement for metrics
  - HTTPRoute for UI access
- ✅ Created App-of-Apps root application pattern
- ✅ Created ArgoCD Application template for Cilium (CNI)
- ✅ Backed up original Flux configuration to `flux-system.backup/`

#### 4. Directory Structure
- ✅ Created `templates/config/kubernetes/argocd/applications/` with subdirectories:
  - `kube-system/` - Core Kubernetes apps
  - `cert-manager/` - Certificate management
  - `network/` - Networking apps
  - `default/` - Default namespace apps

---

## 🚧 Remaining Work

### Phase 1: Complete ArgoCD Application Conversions

#### Kube-System Applications
Convert the following Flux HelmReleases to ArgoCD Applications:
- [ ] `coredns` - DNS server for cluster
- [ ] `metrics-server` - Resource metrics
- [ ] `reloader` - Config reload automation
- [ ] `spegel` - Image registry mirror

**Pattern for conversion:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app-name>
  namespace: argocd
spec:
  project: default
  source:
    repoURL: <helm-repo-url>
    chart: <chart-name>
    targetRevision: <version>
    helm:
      valuesObject:
        # Copy values from HelmRelease
  destination:
    server: https://kubernetes.default.svc
    namespace: <target-namespace>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

#### Cert-Manager
- [ ] Convert `cert-manager/cert-manager` HelmRelease to ArgoCD Application
- [ ] Update ClusterIssuer to use Infomaniak webhook
- [ ] Add Infomaniak webhook deployment (see: https://github.com/Infomaniak/cert-manager-webhook-infomaniak)

#### Network Applications
- [ ] Convert `envoy-gateway` to ArgoCD Application
- [ ] Convert `k8s-gateway` to ArgoCD Application
- [ ] **NEW:** Add Tailscale operator Application

#### Default Namespace
- [ ] Convert `echo` demo app to ArgoCD Application (or remove if not needed)

### Phase 2: Infomaniak Integration

#### DNS & Certificates
- [ ] Deploy cert-manager Infomaniak webhook:
  ```yaml
  source:
    repoURL: https://github.com/Infomaniak/cert-manager-webhook-infomaniak
    path: deploy/cert-manager-webhook-infomaniak
  ```
- [ ] Create ClusterIssuer with Infomaniak DNS-01 solver:
  ```yaml
  apiVersion: cert-manager.io/v1
  kind: ClusterIssuer
  metadata:
    name: letsencrypt-production
  spec:
    acme:
      server: https://acme-v02.api.letsencrypt.org/directory
      privateKeySecretRef:
        name: letsencrypt-production
      solvers:
        - dns01:
            webhook:
              groupName: acme.infomaniak.com
              solverName: infomaniak
              config:
                apiTokenSecretRef:
                  name: infomaniak-credentials
                  key: api-token
  ```
- [ ] Create secret with Infomaniak API token (SOPS-encrypted)

#### External Access Strategy
Since you're using **port forwarding + DynDNS** for public services:
- [ ] Document port forwarding requirements (e.g., forward ports 80/443 to `cluster_external_gateway_addr`)
- [ ] Choose DynDNS provider (DuckDNS, No-IP, Infomaniak DynDNS, etc.)
- [ ] Consider adding a DynDNS updater DaemonSet or CronJob if needed
- [ ] **Note:** Without external-dns, DNS records must be managed manually or via separate automation

### Phase 3: Tailscale Integration

- [ ] Create Tailscale operator ArgoCD Application
- [ ] Reference: https://tailscale.com/kb/1236/kubernetes-operator
- [ ] Create Tailscale OAuth client at https://login.tailscale.com/admin/settings/oauth
- [ ] Store Tailscale auth key in SOPS-encrypted secret
- [ ] Create ArgoCD Application:
  ```yaml
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  metadata:
    name: tailscale-operator
    namespace: argocd
  spec:
    source:
      repoURL: https://pkgs.tailscale.com/helmcharts
      chart: tailscale-operator
      targetRevision: 1.78.x
      helm:
        valuesObject:
          oauth:
            clientId: <from-secret>
            clientSecret: <from-secret>
    destination:
      namespace: tailscale
  ```

### Phase 4: Gitea Integration

#### Repository References
Update the following template files to use Gitea variables:
- [ ] `templates/config/bootstrap/github-deploy-key.sops.yaml.j2` → Rename to `gitea-deploy-key.sops.yaml.j2`
- [ ] Update ArgoCD repository credentials to use `repository_url` variable
- [ ] Update any hardcoded GitHub URLs in templates

#### CI/CD Migration
Your Gitea version 1.23.5 supports Gitea Actions! Convert workflows:

**GitHub Actions → Gitea Actions:**
- [ ] `.github/workflows/flux-local.yaml` → `.gitea/workflows/argocd-validate.yaml`
  - Replace flux-local validation with ArgoCD validation (e.g., `argocd app diff`)
- [ ] `.github/workflows/e2e.yaml` → `.gitea/workflows/e2e.yaml`
  - Update runner labels (Gitea uses different labels)
- [ ] `.github/workflows/renovate.yaml` (if exists) → Keep or move to CronJob
- [ ] Delete `.github/workflows/label-sync.yaml` and `.github/workflows/labeler.yaml` (GitHub-specific)

**Gitea Actions Notes:**
- Workflow syntax is nearly identical to GitHub Actions
- Need to set up Gitea Actions runner: https://docs.gitea.com/usage/actions/quickstart
- Can reuse most workflow steps, just change runner labels

#### Renovate Configuration
- [ ] Update `.renovaterc.json5`:
  ```json5
  {
    "platform": "gitea",
    "endpoint": "https://your-gitea-instance.com/api/v1",
    "gitAuthor": "Renovate Bot <renovate@example.com>",
    // ... rest of config
  }
  ```
- [ ] Run Renovate as:
  - Option 1: Gitea Actions workflow (cron trigger)
  - Option 2: Kubernetes CronJob with Renovate container
  - Option 3: External cron job on workstation

### Phase 5: Bootstrap Process Updates

#### Update Bootstrap Scripts
The bootstrap process needs significant changes:

**Current Flux bootstrap:** (`scripts/bootstrap-apps.sh`)
```bash
# Install Flux CRDs
kubectl apply -k kubernetes/apps/flux-system

# Wait for Flux to reconcile
flux reconcile kustomization cluster-apps --with-source
```

**New ArgoCD bootstrap:**
```bash
# 1. Install ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values kubernetes/apps/argocd/argocd/app/values.yaml

# 2. Wait for ArgoCD to be ready
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# 3. Apply SOPS age key secret
kubectl apply -f kubernetes/components/sops/cluster-secrets.sops.yaml

# 4. Apply Git repository credentials
kubectl apply -f kubernetes/apps/argocd/argocd/app/secret.sops.yaml

# 5. Deploy root App-of-Apps
kubectl apply -f kubernetes/apps/argocd/app-of-apps/app/root-app.yaml

# 6. Watch ArgoCD sync all applications
argocd app list
argocd app sync cluster-apps
```

**Files to update:**
- [ ] `scripts/bootstrap-apps.sh` - Main bootstrap script
- [ ] `.taskfiles/bootstrap/Taskfile.yaml` - Task automation
- [ ] `.mise.toml` - Remove `flux2` CLI, add `argocd` CLI

#### Update Taskfile
- [ ] `task bootstrap:apps` should install ArgoCD instead of Flux
- [ ] `task reconcile` should use `argocd app sync` instead of `flux reconcile`

### Phase 6: Documentation

- [ ] Update `README.md`:
  - Replace Flux references with ArgoCD
  - Replace Cloudflare setup with Infomaniak/Tailscale/DynDNS
  - Replace GitHub references with Gitea
  - Update Stage 3 (remove Cloudflare tunnel setup)
  - Update Stage 4 (configure Infomaniak API token)
  - Update Stage 5 (ArgoCD bootstrap process)
  - Add Tailscale setup instructions
- [ ] Create `docs/ARGOCD.md` - ArgoCD usage guide
- [ ] Create `docs/INFOMANIAK.md` - Infomaniak integration guide
- [ ] Create `docs/TAILSCALE.md` - Tailscale VPN access guide

---

## Architecture Comparison

### Before (Original Template)
```
┌─────────────────────────────────────────────────────┐
│ GitHub Repository                                    │
│ ├── Flux Kustomizations                             │
│ ├── Flux HelmReleases                               │
│ └── Flux GitRepository                               │
└─────────────────────────────────────────────────────┘
                    ↓
        ┌───────────────────────┐
        │ Flux Operator         │
        │ + Flux Instance       │
        └───────────────────────┘
                    ↓
    ┌───────────────────────────────────┐
    │ Applications                       │
    │ ├── Cilium (CNI)                  │
    │ ├── CoreDNS                       │
    │ ├── Cloudflare Tunnel             │
    │ ├── Cloudflare DNS (external-dns) │
    │ ├── cert-manager (CF DNS-01)      │
    │ └── ...                            │
    └───────────────────────────────────┘
                    ↓
    External Access: Cloudflare Tunnel → Internet
```

### After (Migrated)
```
┌─────────────────────────────────────────────────────┐
│ Gitea Repository                                     │
│ ├── ArgoCD Applications                             │
│ ├── Helm Values                                     │
│ └── Kustomize Overlays                              │
└─────────────────────────────────────────────────────┘
                    ↓
        ┌───────────────────────┐
        │ ArgoCD                 │
        │ + SOPS Plugin          │
        └───────────────────────┘
                    ↓
    ┌───────────────────────────────────┐
    │ Applications                       │
    │ ├── Cilium (CNI)                  │
    │ ├── CoreDNS                       │
    │ ├── Tailscale Operator            │
    │ ├── cert-manager (Infomaniak)     │
    │ ├── Envoy Gateway                 │
    │ └── ...                            │
    └───────────────────────────────────┘
                    ↓
    External Access:
    - Public services: Port Forwarding (80/443) → Envoy Gateway
    - Private access: Tailscale VPN
    - DNS: Manual or Infomaniak API (via cert-manager webhook)
```

---

## Key Design Decisions

### 1. **No external-dns Replacement**
- **Reason:** Infomaniak doesn't have native external-dns support
- **Solution:** Manual DNS management OR use cert-manager's Infomaniak webhook for DNS updates
- **Alternative:** Could build a custom external-dns webhook for Infomaniak (complex)

### 2. **Port Forwarding Instead of Cloudflare Tunnel**
- **Public services** (Nextcloud, Immich): Port forward 80/443 → `cluster_external_gateway_addr`
- **Requires:** Static IP or DynDNS service
- **Security:** Use cert-manager for TLS, Envoy Gateway for routing

### 3. **Tailscale for Private Access**
- **Use case:** Accessing cluster services from anywhere without exposing publicly
- **Integration:** Tailscale Kubernetes operator
- **Benefit:** Mesh VPN, no port forwarding needed for private services

### 4. **ArgoCD SOPS Integration**
- **Method:** Custom plugin in repo-server
- **Age key:** Mounted as secret in argocd-repo-server pod
- **Decryption:** Happens during manifest generation, transparent to ArgoCD

### 5. **Talos Linux Retained**
- **Decision:** Keep Talos (not switching to K3s)
- **Reason:** Talos provides immutable infrastructure benefits
- **Note:** Sticking with full Kubernetes, not K3s

---

## Testing Checklist

Before deploying to production, test the following:

- [ ] Template rendering: `task configure` succeeds without errors
- [ ] SOPS encryption: All `.sops.yaml` files are properly encrypted
- [ ] ArgoCD installation: Helm install succeeds
- [ ] ArgoCD can access Gitea repository (SSH deploy key works)
- [ ] SOPS plugin decrypts secrets correctly
- [ ] Cilium deploys and cluster networking works
- [ ] cert-manager Infomaniak webhook can create DNS records
- [ ] TLS certificates are issued successfully
- [ ] Port forwarding works for external services
- [ ] Tailscale operator provides VPN access
- [ ] All applications sync and become healthy in ArgoCD

---

## Rollback Plan

If migration fails:
1. Restore from `flux-system.backup/` directory
2. Revert `cluster.yaml` changes
3. Re-apply Flux bootstrap process
4. Investigate issues and retry migration

---

## Next Steps

1. **Complete ArgoCD Application conversions** for all remaining apps
2. **Test the bootstrap process** in a staging environment
3. **Set up Infomaniak API access** and test cert-manager webhook
4. **Configure Tailscale OAuth client** and test operator deployment
5. **Update all documentation** with new procedures
6. **Migrate GitHub Actions** to Gitea Actions
7. **Test end-to-end** deployment from scratch

---

## Questions / Decisions Needed

- [ ] DynDNS provider choice (DuckDNS, No-IP, Infomaniak DynDNS)?
- [ ] Should we auto-update DNS via cron job or keep it manual?
- [ ] Renovate deployment method (Gitea Actions, CronJob, or external)?
- [ ] Which applications from the original template do you want to keep/remove?
- [ ] Do you want to deploy Hubble (Cilium observability) now that Talos is confirmed?

---

**Generated:** $(date)
**Migration Branch:** `claude/argocd-infomaniak-dns-...`
**Status:** 🚧 In Progress - Foundation Complete, Applications Need Conversion
