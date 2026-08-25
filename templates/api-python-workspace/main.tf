terraform {
  required_version = ">= 1.5.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

# Fine-grained PAT scoped to the api-python repo (private) — never written to the pod spec.
variable "github_token" {
  description = "GitHub fine-grained PAT for cloning api-python and workspace Git operations"
  type        = string
  sensitive   = true
}

# ── Workspace parameters ───────────────────────────────────────────────────────

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "repo_url" {
  name         = "repo_url"
  display_name = "Git Repository"
  description  = "Repository to clone on workspace start"
  default      = "https://github.com/patelajk2319-coder/api-python"
  type         = "string"
  mutable      = true
}

data "coder_parameter" "instance_size" {
  name         = "instance_size"
  display_name = "Workspace Size"
  description  = "Sizes the workspace container. The Docker-in-Docker sidecar is sized separately, fixed regardless of this choice."
  default      = "medium"
  type         = "string"
  mutable      = false

  option {
    name  = "Small  (1 CPU / 2 GB)"
    value = "small"
  }
  option {
    name  = "Medium (2 CPU / 4 GB)"
    value = "medium"
  }
  option {
    name  = "Large  (4 CPU / 8 GB)"
    value = "large"
  }
}

# ── Resource sizing ────────────────────────────────────────────────────────────

locals {
  sizes = {
    small  = { cpu_req = "1", cpu_lim = "2", mem_req = "2Gi", mem_lim = "4Gi" }
    medium = { cpu_req = "2", cpu_lim = "4", mem_req = "4Gi", mem_lim = "8Gi" }
    large  = { cpu_req = "4", cpu_lim = "6", mem_req = "8Gi", mem_lim = "12Gi" }
  }
  size = local.sizes[data.coder_parameter.instance_size.value]

  workspace_namespace = "coder-ws-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
}

# ── Workspace namespace ────────────────────────────────────────────────────────

resource "kubernetes_namespace" "workspace" {
  metadata {
    name = local.workspace_namespace
    labels = {
      "coder.com/workspace-id"    = data.coder_workspace.me.id
      "coder.com/workspace-owner" = data.coder_workspace_owner.me.name
    }
  }
}

# ── Network policy — egress allowlist ─────────────────────────────────────────
# Docker image pulls from inside the dind sidecar (registry auth + layer
# blobs) go over 443 same as any other HTTPS traffic — no separate rule needed.

resource "kubernetes_network_policy" "workspace_egress" {
  metadata {
    name      = "workspace-egress"
    namespace = kubernetes_namespace.workspace.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      ports {
        port     = "53"
        protocol = "UDP"
      }
    }

    egress {
      ports {
        port     = "443"
        protocol = "TCP"
      }
    }

    egress {
      ports {
        port     = "80"
        protocol = "TCP"
      }
    }
  }
}

# ── Persistent home directory ──────────────────────────────────────────────────

resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "home"
    namespace = kubernetes_namespace.workspace.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "gp3"
    resources {
      requests = { storage = "10Gi" }
    }
  }

  wait_until_bound = false
}

# ── Coder workspace agent ──────────────────────────────────────────────────────

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"

  env = {
    GITHUB_TOKEN = var.github_token
    # dind sidecar shares this pod's network namespace — reachable over localhost.
    DOCKER_HOST = "tcp://localhost:2375"
  }

  # Blocking: agent doesn't report ready until startup script exits.
  startup_script_behavior = "blocking"

  startup_script = <<-EOT
    #!/bin/bash
    set -e

    # Tools install into $HOME/.local/bin on the PVC — first boot installs, restarts skip.
    mkdir -p "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"
    grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" || \
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"

    # ── Git identity ───────────────────────────────────────────────────────────
    git config --global user.name  "${data.coder_workspace_owner.me.full_name != "" ? data.coder_workspace_owner.me.full_name : data.coder_workspace_owner.me.name}"
    git config --global user.email "${data.coder_workspace_owner.me.email}"

    # ── Git credentials ────────────────────────────────────────────────────────
    git config --global credential.https://github.com.helper \
      "!f() { echo username=x-access-token; echo password=$${GITHUB_TOKEN}; }; f"

    # ── Docker CLI (talks to the dind sidecar over DOCKER_HOST) ───────────────
    if ! command -v docker &>/dev/null; then
      DOCKER_CLI_VERSION="27.3.1"
      curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-$${DOCKER_CLI_VERSION}.tgz" -o /tmp/docker.tgz
      tar -xzf /tmp/docker.tgz -C /tmp docker/docker
      mv /tmp/docker/docker "$HOME/.local/bin/docker"
      rm -rf /tmp/docker.tgz /tmp/docker
    fi

    # ── go-task (drives api-python's own Taskfile — task build/test/run) ─────
    if ! command -v task &>/dev/null; then
      sh -c "$(curl -fsSL https://taskfile.dev/install.sh)" -- -d -b "$HOME/.local/bin" 2>/dev/null
    fi

    # ── Code Server ─────────────────────────────────────────────────────────
    if ! command -v code-server &>/dev/null; then
      curl -fsSL https://code-server.dev/install.sh \
        | sh -s -- --method=standalone --prefix="$HOME/.local" 2>&1 | tail -3
    fi

    SETTINGS_FILE="$HOME/.local/share/code-server/User/settings.json"
    if [[ ! -f "$SETTINGS_FILE" ]]; then
      mkdir -p "$(dirname "$SETTINGS_FILE")"
      cat > "$SETTINGS_FILE" <<'SETTINGS'
{
  "workbench.colorTheme": "Default Dark Modern"
}
SETTINGS
    fi

    for ext in ms-python.python ms-azuretools.vscode-docker; do
      code-server --install-extension "$ext" --force &>/dev/null || true
    done

    code-server \
      --auth none \
      --port 13337 \
      --disable-telemetry \
      "$HOME" > /tmp/code-server.log 2>&1 &

    # ── Clone (or update) repository ───────────────────────────────────────────
    # $HOME is a persistent PVC — on a restart this directory already exists
    # from a previous boot, so pull the latest instead of only cloning once.
    REPO_DIR="$HOME/$(basename "${data.coder_parameter.repo_url.value}" .git)"
    if [[ ! -d "$REPO_DIR" ]]; then
      git clone --depth=1 "${data.coder_parameter.repo_url.value}" "$REPO_DIR"
    else
      git -C "$REPO_DIR" pull --ff-only \
        || echo "[warn] $REPO_DIR has local changes — skipped pulling latest"
    fi

    # ── Docker-in-Docker demo: build and run api-python against the sidecar ──
    for i in $(seq 1 30); do
      docker version &>/dev/null && break
      sleep 1
    done

    cd "$REPO_DIR"
    task build
  EOT

  metadata {
    display_name = "CPU"
    key          = "cpu_usage"
    script       = "coder stat cpu"
    interval     = 5
    timeout      = 5
  }

  metadata {
    display_name = "Memory"
    key          = "mem_usage"
    script       = "coder stat mem"
    interval     = 5
    timeout      = 5
  }

  metadata {
    display_name = "Disk"
    key          = "disk"
    script       = "coder stat disk --path $HOME"
    interval     = 60
    timeout      = 5
  }
}

# ── Developer-facing access note ────────────────────────────────────────────────
# Shown directly on the workspace page in the dashboard. Developers should
# never need this repo, its .env, or admin credentials just to reach their own
# workspace's API from a local tool — `coder port-forward` works for any
# authenticated Coder user against workspaces they own.

resource "coder_metadata" "api_access" {
  count       = data.coder_workspace.me.start_count
  resource_id = kubernetes_pod.workspace[0].id

  item {
    key   = "Local API access"
    value = "coder port-forward ${data.coder_workspace.me.name} --tcp 8000:8000"
  }
}

# ── App shortcuts ──────────────────────────────────────────────────────────────

resource "coder_app" "code_server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code (Browser)"
  url          = "http://localhost:13337/?folder=/home/coder/${basename(trimsuffix(data.coder_parameter.repo_url.value, ".git"))}"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "coder_app" "terminal" {
  agent_id     = coder_agent.main.id
  slug         = "terminal"
  display_name = "Terminal"
  command      = "/bin/bash"
  icon         = "/icon/terminal.svg"
}

resource "coder_app" "api_python" {
  agent_id     = coder_agent.main.id
  slug         = "api-python"
  display_name = "api-python (docs)"
  url          = "http://localhost:8000/docs"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8000/docs"
    interval  = 5
    threshold = 6
  }
}

# ── Workspace pod ──────────────────────────────────────────────────────────────

resource "kubernetes_pod" "workspace" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
    namespace = kubernetes_namespace.workspace.metadata[0].name
    labels = {
      "app"                       = "coder-workspace"
      "coder.com/workspace-id"    = data.coder_workspace.me.id
      "coder.com/workspace-name"  = data.coder_workspace.me.name
      "coder.com/workspace-owner" = data.coder_workspace_owner.me.name
    }
    annotations = {
      "coder.com/workspace-id" = data.coder_workspace.me.id
    }
  }

  spec {
    security_context {
      run_as_user     = 1000
      run_as_non_root = true
      fs_group        = 1000
    }

    # Prevents lateral movement via the K8s API from a compromised workspace.
    automount_service_account_token = false

    container {
      name    = "workspace"
      image   = "codercom/enterprise-base:ubuntu"
      command = ["/bin/bash", "-c", coder_agent.main.init_script]

      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }

      resources {
        requests = {
          cpu    = local.size.cpu_req
          memory = local.size.mem_req
        }
        limits = {
          cpu    = local.size.cpu_lim
          memory = local.size.mem_lim
        }
      }

      volume_mount {
        mount_path = "/home/coder"
        name       = "home"
      }
    }

    # Docker-in-Docker sidecar — privileged, root, shares the pod network
    # namespace so the workspace container reaches it over localhost:2375.
    # Scoped to this one pod, still bound by the namespace's egress
    # NetworkPolicy above.
    container {
      name  = "dind"
      image = "docker:27-dind"

      security_context {
        privileged      = true
        run_as_user     = 0
        run_as_non_root = false
      }

      env {
        name  = "DOCKER_TLS_CERTDIR"
        value = ""
      }

      args = ["--host=tcp://0.0.0.0:2375"]

      resources {
        requests = {
          cpu    = "250m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }

      volume_mount {
        mount_path = "/var/lib/docker"
        name       = "docker-lib"
      }
    }

    volume {
      name = "home"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.home.metadata[0].name
      }
    }

    # Not persisted across restarts — dind's storage is rebuilt via `docker build`
    # in the startup script, so there's no need to burn a PVC on it.
    volume {
      name = "docker-lib"
      empty_dir {}
    }
  }
}
