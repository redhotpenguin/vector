terraform {
  required_providers {
    kubernetes = {
      version = "~> 2.5.0"
      source  = "hashicorp/kubernetes"
    }
  }
}

provider "kubernetes" {
  #  config_context_cluster = "datadog-agent-remap-datadog-logs" # TODO make a varianble
  config_path = "~/.kube/config"
}
