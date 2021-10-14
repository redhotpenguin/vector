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
#  config_context = "minikube"
  # config_context_name = "minikube"
  # host = "192.168.39.22"
}

resource "kubernetes_namespace" "vector" {
  metadata {
    name = "vector"
  }
}


resource "kubernetes_deployment" "vector" {
  metadata {
    name = "vector"
    namespace = kubernetes_namespace.vector.metadata[0].name
    labels = {
      soak_test   = "foobar"
      sha         = "2foobar"
      feature_sha = "bingbang"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        soak_test   = "foobar"
        sha         = "2foobar"
        feature_sha = "bingbang"
      }
    }

    template {
      metadata {
        labels = {
          soak_test   = "foobar"
          sha         = "2foobar"
          feature_sha = "bingbang"
        }
      }

      spec {
        automount_service_account_token = false
        container {
          image_pull_policy = "IfNotPresent"
          image = "vector:17d9af99443665c02ef20aa20504eb4782047e72-4f5ab2fb2f82b57a23076b9db90bcd2e335c0f0b"
          name  = "vector"

          resources {
            limits = {
              cpu    = "250m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
          }
        }
      }
    }
  }
}
