# Modul 3, cwiczenie 18 (⭐Stretch): library panel jako zasob Terraform w Labie wspolnym.
# Provider grafana/grafana, zasob grafana_library_panel (subcategory "Grafana OSS").
#
#   export TF_VAR_grafana_auth="<login>:<haslo>"   # basic auth imiennego konta
#   export TF_VAR_login="<login>"
#   export TF_VAR_folder_uid="<UID folderu Uczestnicy/<login>>"
#   terraform init && terraform apply
#   # zmien model w 03-lp-p95-latency.model.json, potem:
#   terraform plan    # diff na model_json
#   terraform destroy # sprzatanie po cwiczeniu
#
# W organizacji wlasny folder standardow (View dla wszystkich, Edit dla wlasciciela)
# zakladasz zasobem grafana_folder i uprawnieniami grafana_folder_permission.
# W Labie wspolnym uzywasz swojego folderu uczestnika.

terraform {
  required_version = ">= 1.5"
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.46"
    }
  }
}

variable "grafana_url" {
  type    = string
  default = "https://grafana.workshop2.indexoutofrange.com"
}

# "login:haslo" (basic auth) albo token service account.
variable "grafana_auth" {
  type      = string
  sensitive = true
}

variable "login" {
  type = string
}

variable "folder_uid" {
  type = string
}

provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_auth
}

resource "grafana_library_panel" "p95_latency" {
  uid        = "${var.login}-std-p95"
  name       = "p95 latency (standard, ${var.login})"
  folder_uid = var.folder_uid
  model_json = file("${path.module}/03-lp-p95-latency.model.json")
}

output "library_panel_version" {
  value = grafana_library_panel.p95_latency.version
}
