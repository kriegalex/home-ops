# ⛵ Kubernetes Cluster Template (ArgoCD Edition)

Welcome to this template for deploying a production-ready Kubernetes cluster on bare-metal or VMs. This template provides a GitOps-driven approach to managing your homelab infrastructure with modern tools and best practices.

This template is based on [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template) but adapted for:
- **ArgoCD** instead of Flux for GitOps
- **Infomaniak DNS** instead of Cloudflare
- **Gitea** support instead of GitHub-only
- **Tailscale** for VPN access (optional)
- **Talos Linux** for immutable infrastructure

At its core, this project uses [makejinja](https://github.com/mirkolenz/makejinja) to render templates from configuration files ([cluster.yaml](./cluster.sample.yaml) and [nodes.yaml](./nodes.sample.yaml)), generating everything needed to deploy and manage your cluster.

## ✨ Features

A Kubernetes cluster deployed with:
- **OS:** [Talos Linux](https://github.com/siderolabs/talos) - Immutable, Kubernetes-optimized
- **GitOps:** [ArgoCD](https://argoproj.github.io/cd/) - Declarative cluster state management
- **Git Provider:** [Gitea](https://gitea.io/) (or GitHub/GitLab) - Flexible repository hosting
- **Secrets:** [SOPS](https://github.com/getsops/sops) with [age](https://github.com/FiloSottile/age) encryption
- **DNS:** [Infomaniak](https://www.infomaniak.com/) for domain management (DNS-01 ACME challenges)
- **VPN:** [Tailscale](https://tailscale.com/) for secure private access (optional)

**Included Components:**
- [cilium](https://github.com/cilium/cilium) - CNI with eBPF-based networking
- [cert-manager](https://github.com/cert-manager/cert-manager) - TLS certificate automation
- [envoy-gateway](https://github.com/envoyproxy/gateway) - Kubernetes-native API gateway
- [k8s-gateway](https://github.com/k8s-gateway/k8s-gateway) - Internal DNS for cluster services
- [spegel](https://github.com/spegel-org/spegel) - P2P image registry mirror
- [reloader](https://github.com/stakater/Reloader) - Automatic config/secret reload
- [metrics-server](https://github.com/kubernetes-sigs/metrics-server) - Resource metrics

**Additional Features:**
- Dev environment managed with [mise](https://mise.jdx.dev/)
- Template-driven configuration
- Dependency automation with [Renovate](https://www.mend.io/renovate)
- SOPS-encrypted secrets in Git
- App-of-Apps pattern for ArgoCD

## 📋 Prerequisites

**Required Knowledge:**
- [Containers](https://opencontainers.org/) and [Kubernetes](https://kubernetes.io/) basics
- [YAML](https://yaml.org/) syntax
- [Git](https://git-scm.com/) fundamentals

**Required Accounts/Services:**
- **Domain name** managed by Infomaniak (or another DNS provider)
- **Git repository** (Gitea, GitHub, or GitLab)
- **Infomaniak API access** (for automated DNS-01 challenges)
- _Optional:_ **Tailscale account** (for VPN access)

**Hardware Requirements:**
- **Minimum:** 1 node with 4 CPU cores, 16GB RAM, 256GB SSD/NVMe
- **Recommended:** 3+ controller nodes for high availability

## 🚀 Getting Started

### Stage 1: Machine Preparation

> [!IMPORTANT]
> For high availability, deploy **3+ controller nodes**. This template configures all nodes to run workloads, so worker nodes are optional.

1. **Create Talos Linux boot media:**
   - Visit [Talos Linux Image Factory](https://factory.talos.dev)
   - Select **bare-minimum system extensions** (add more later as needed)
   - Download ISO (bare-metal) or RAW image (SBCs)
   - **Note the schematic ID** for later use

2. **Boot your nodes:**
   - Flash the image to USB drive
   - Boot each node from the USB
   - Verify nodes are reachable: `nmap -Pn -n -p 50000 192.168.1.0/24 -vv | grep 'Discovered'`

### Stage 2: Local Workstation Setup

1. **Create your repository:**
   ```sh
   # Using GitHub (or adapt for Gitea/GitLab)
   export REPONAME="home-ops"
   gh repo create $REPONAME --template YOUR_USERNAME/cluster-template --public --clone
   cd $REPONAME
   ```

2. **Install Mise CLI:**
   - Follow the [Mise installation guide](https://mise.jdx.dev/getting-started.html#installing-mise-cli)
   - Activate Mise in your shell: [activation guide](https://mise.jdx.dev/getting-started.html#activate-mise)

3. **Install required tools:**
   ```sh
   mise trust
   pip install pipx
   mise install
   ```

   This installs: `kubectl`, `helm`, `argocd`, `talosctl`, `sops`, `age`, `kustomize`, and more

### Stage 3: DNS & External Access Setup

#### Option A: Infomaniak DNS (Recommended)

1. **Create Infomaniak API token:**
   - Go to [Infomaniak API Manager](https://manager.infomaniak.com/v3/infomaniak-api)
   - Create token with scopes: `domain:read`, `dns:read`, `dns:write`
   - Save token securely

2. **Configure external access:**
   - **For public services (Nextcloud, etc.):**
     - Port forward ports 80/443 from router → `cluster_external_gateway_addr`
     - Set up DynDNS if you have dynamic IP (DuckDNS, No-IP, Infomaniak DynDNS)

   - **For private services (optional):**
     - Set up [Tailscale](https://tailscale.com/)
     - Create OAuth client at [Tailscale Admin](https://login.tailscale.com/admin/settings/oauth)

#### Option B: Other DNS Providers

- **Cloudflare:** Use original template (not this fork)
- **Manual DNS:** Set `infomaniak_api_token` to empty, manage DNS records manually

### Stage 4: Cluster Configuration

1. **Initialize configuration:**
   ```sh
   task init
   ```

2. **Edit configuration files:**

   **`cluster.yaml` - Core settings:**
   ```yaml
   # Network
   node_cidr: "192.168.1.0/24"
   cluster_api_addr: "192.168.1.100"  # VIP for Kubernetes API
   cluster_gateway_addr: "192.168.1.101"  # Internal gateway
   cluster_external_gateway_addr: "192.168.1.102"  # External gateway
   cluster_dns_gateway_addr: "192.168.1.103"  # DNS gateway

   # Domain & DNS
   cluster_domain: "example.com"
   infomaniak_api_token: "YOUR_INFOMANIAK_TOKEN"

   # Git Repository
   repository_url: "https://gitea.example.com/user/home-ops"
   repository_name: "user/home-ops"
   repository_type: "gitea"  # or "github", "gitlab"

   # Optional: Tailscale VPN
   # tailscale_enabled: true
   # tailscale_auth_key: "YOUR_TAILSCALE_KEY"
   ```

   **`nodes.yaml` - Node definitions:**
   ```yaml
   nodes:
     - name: controller-1
       address: 192.168.1.10
       controller: true
       disk: /dev/sda
       mac_addr: "aa:bb:cc:dd:ee:01"
       schematic_id: "abc123..."
   ```

3. **Render templates:**
   ```sh
   task configure
   ```

   This generates:
   - `kubernetes/` - ArgoCD Applications and manifests
   - `talos/` - Talos cluster configuration
   - `bootstrap/` - Initial secrets

4. **Encrypt secrets with SOPS:**
   ```sh
   # Generate age key (first time only)
   age-keygen -o age.key

   # Create .sops.yaml configuration
   cat > .sops.yaml <<EOF
   creation_rules:
     - path_regex: .*\.sops\.yaml$
       age: >-
         $(cat age.key | grep public | sed 's/# public key: //')
   EOF

   # Encrypt all .sops.yaml files
   find . -name "*.sops.yaml" -exec sops --encrypt --in-place {} \;
   ```

5. **Commit configuration:**
   ```sh
   # Verify all .sops.yaml files are encrypted
   grep -r "ENC\[AES256" kubernetes/

   git add -A
   git commit -m "feat: initial cluster configuration"
   git push
   ```

6. **Add deploy key to Git repository:**
   - Generate: `ssh-keygen -t ed25519 -C "argocd@cluster" -f argocd-deploy-key`
   - Add public key to Gitea: Settings → Deploy Keys → Add Deploy Key
   - Encrypt private key in `kubernetes/apps/argocd/argocd/app/secret.sops.yaml`

### Stage 5: Bootstrap Cluster

> [!WARNING]
> Bootstrap takes 10-15 minutes. You'll see errors like "couldn't get current server API group list" - this is normal during CNI installation.

1. **Bootstrap Talos:**
   ```sh
   task bootstrap:talos
   ```

   This will:
   - Generate Talos machine configs
   - Apply configs to nodes
   - Bootstrap Kubernetes control plane
   - Generate kubeconfig

2. **Commit Talos secrets:**
   ```sh
   git add talos/
   git commit -m "chore: add talos encrypted secrets"
   git push
   ```

3. **Bootstrap ArgoCD and applications:**
   ```sh
   task bootstrap:apps
   ```

   This will:
   - Install Cilium (CNI)
   - Install CoreDNS
   - Install ArgoCD via Helm
   - Apply SOPS secrets
   - Deploy root App-of-Apps
   - Sync all applications

4. **Monitor deployment:**
   ```sh
   # Watch all pods
   kubectl get pods -A --watch

   # Or use ArgoCD UI
   task argocd:dashboard  # Opens port-forward to localhost:8080
   # Get admin password: task argocd:password
   # Access: https://localhost:8080
   ```

## 📣 Post-Installation

### ✅ Verification

1. **Check Cilium status:**
   ```sh
   cilium status
   ```

2. **Check ArgoCD applications:**
   ```sh
   argocd app list
   argocd app get cluster-apps
   ```

   Or use the UI at `https://localhost:8080` (after running `task argocd:dashboard`)

3. **Verify gateways:**
   ```sh
   # Test internal gateway
   nmap -Pn -n -p 443 ${cluster_gateway_addr}

   # Test external gateway (should be reachable from router port-forward)
   nmap -Pn -n -p 443 ${cluster_external_gateway_addr}
   ```

4. **Test DNS resolution:**
   ```sh
   # Internal DNS (from cluster or local network)
   dig @${cluster_dns_gateway_addr} echo.${cluster_domain}

   # Should return ${cluster_gateway_addr}
   ```

5. **Check TLS certificates:**
   ```sh
   kubectl -n cert-manager get certificates
   kubectl -n cert-manager get clusterissuers
   ```

### 🌐 Public vs Private Access

**Public Services** (Nextcloud, Immich, etc.):
- Use `envoy-external` gateway in HTTPRoute
- Accessible via `https://service.example.com` (through port-forwarded router)
- Requires ports 80/443 forwarded to `cluster_external_gateway_addr`

**Private Services** (ArgoCD, internal tools):
- Use `envoy-internal` gateway in HTTPRoute
- Accessible only from local network (or via Tailscale if enabled)
- DNS resolved by `k8s-gateway`

### 🏠 Split DNS Setup

Configure your home DNS server (Pi-hole, Dnsmasq, etc.) to forward queries for `${cluster_domain}` to `${cluster_dns_gateway_addr}`:

**Pi-hole:**
```
# /etc/dnsmasq.d/02-k8s-gateway.conf
server=/example.com/192.168.1.103
```

**Dnsmasq:**
```
server=/example.com/192.168.1.103
```

### 🔄 GitOps Workflow

**Making changes:**
```sh
# 1. Edit configuration files
vim cluster.yaml  # or nodes.yaml, application values, etc.

# 2. Re-render templates
task configure

# 3. Commit and push
git add -A
git commit -m "feat: update configuration"
git push

# 4. Force ArgoCD sync (or wait for automatic sync)
task reconcile
```

**ArgoCD will automatically:**
- Detect Git changes (every 3 minutes by default)
- Sync applications to desired state
- Self-heal if manual changes are made
- Prune removed resources

## 🛠️ Maintenance

### ArgoCD Commands

```sh
# Force sync all apps
task reconcile

# Open ArgoCD UI
task argocd:dashboard  # https://localhost:8080

# Get admin password
task argocd:password

# Login to ArgoCD CLI
task argocd:login
```

### Talos Maintenance

```sh
# Update node configuration
task talos:apply-node IP=192.168.1.10 MODE=auto

# Upgrade Talos version
task talos:upgrade-node IP=192.168.1.10

# Upgrade Kubernetes version
task talos:upgrade-k8s
```

### Adding New Applications

1. Create ArgoCD Application manifest:
   ```yaml
   # templates/config/kubernetes/argocd/applications/my-namespace/my-app.yaml.j2
   ---
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: my-app
     namespace: argocd
   spec:
     project: default
     source:
       repoURL: https://charts.example.com
       chart: my-app
       targetRevision: 1.0.0
       helm:
         valuesObject:
           # Your values here
     destination:
       server: https://kubernetes.default.svc
       namespace: my-namespace
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
   ```

2. Add to kustomization:
   ```yaml
   # templates/config/kubernetes/argocd/applications/my-namespace/kustomization.yaml.j2
   resources:
     - ./my-app.yaml
   ```

3. Include in main kustomization:
   ```yaml
   # templates/config/kubernetes/argocd/applications/kustomization.yaml.j2
   resources:
     - ./my-namespace
   ```

4. Re-render and commit:
   ```sh
   task configure
   git add -A && git commit -m "feat: add my-app" && git push
   ```

## 🤖 Renovate

[Renovate](https://www.mend.io/renovate) automates dependency updates for:
- Helm charts
- Container images
- Mise tools
- Gitea Actions (if using Gitea Actions)

**Setup for Gitea:**
1. Run Renovate as CronJob in cluster or external service
2. Set environment variables:
   ```sh
   RENOVATE_PLATFORM=gitea
   RENOVATE_ENDPOINT=https://gitea.example.com/api/v1
   RENOVATE_TOKEN=<your-gitea-token>
   ```

**Configuration:** [.renovaterc.json5](./.renovaterc.json5)

## 💥 Reset Cluster

> [!CAUTION]
> This will destroy your cluster and reset nodes to maintenance mode.

```sh
task talos:reset
```

## 📚 Additional Documentation

- **[MIGRATION.md](./MIGRATION.md)** - Migration guide from Flux/Cloudflare/GitHub
- **[ArgoCD Documentation](https://argo-cd.readthedocs.io/)** - Official ArgoCD docs
- **[Talos Documentation](https://www.talos.dev/)** - Talos Linux guides
- **[Infomaniak API](https://developer.infomaniak.com/)** - API documentation

## 🆘 Troubleshooting

### Pods not starting (CNI issues)
```sh
cilium status
kubectl -n kube-system logs -l app.kubernetes.io/name=cilium
```

### Certificates not issuing
```sh
kubectl -n cert-manager logs -l app.kubernetes.io/name=cert-manager
kubectl -n cert-manager get challenges
```

### ArgoCD sync failures
```sh
argocd app get <app-name>
argocd app logs <app-name>
```

### DNS resolution issues
```sh
kubectl -n network logs -l app.kubernetes.io/name=k8s-gateway
dig @${cluster_dns_gateway_addr} test.${cluster_domain}
```

## 🙏 Acknowledgments

- Original template by [onedr0p](https://github.com/onedr0p/cluster-template)
- [Kubernetes@Home](https://github.com/k8s-at-home) community
- [ArgoCD](https://argoproj.github.io/) project
- [Talos Linux](https://www.talos.dev/) team

## 📝 License

See [LICENSE](./LICENSE)
