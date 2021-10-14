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


resource "kubernetes_config_map" "vector" {
  metadata {
    name = "vector"
    namespace = kubernetes_namespace.vector.metadata[0].name
  }

  data = {
    "vector.toml" = "${file("${path.module}/vector.toml")}"
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
          image = "localhost/vector:e4805b823ae5df1bc19307a22d856627f4e57e91-4f5ab2fb2f82b57a23076b9db90bcd2e335c0f0b"
          name  = "vector"

          volume_mount {
            mount_path = "/var/lib/vector"
            name = "var-lib-vector"
          }

          volume_mount {
            mount_path = "/etc/vector"
            name = "etc-vector"
read_only = true
          }

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

        volume {
          name = "var-lib-vector"
            empty_dir {}
          }
        volume {
          name = "etc-vector"
          config_map {
            name = kubernetes_config_map.vector.metadata[0].name
          }
        }

      }
    }
  }
}
