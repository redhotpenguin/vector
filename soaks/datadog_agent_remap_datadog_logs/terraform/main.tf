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
    name      = "vector"
    namespace = kubernetes_namespace.vector.metadata[0].name
  }

  data = {
    "vector.toml" = "${file("${path.module}/vector.toml")}"
  }
}

resource "kubernetes_service" "vector" {
  metadata {
    name      = "vector"
    namespace = kubernetes_namespace.vector.metadata[0].name
  }
  spec {
    selector = {
      soak_test   = kubernetes_deployment.vector.metadata.0.labels.soak_test
      sha         = kubernetes_deployment.vector.metadata.0.labels.sha
      feature_sha = kubernetes_deployment.vector.metadata.0.labels.feature_sha
    }
    session_affinity = "ClientIP"
    port {
      name        = "datadog-agent"
      port        = 8282
      target_port = 8282
    }
    port {
      name        = "prom-export"
      port        = 9598
      target_port = 9598
    }
    type = "LoadBalancer"
  }
}


resource "kubernetes_deployment" "vector" {
  metadata {
    name      = "vector"
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
        annotations = {
          "prometheus.io/scrape" = true
          "prometheus.io/port" = 9598
          "prometheus.io/path" = "/metrics"
        }
      }

      spec {
        automount_service_account_token = false
        container {
          image_pull_policy = "IfNotPresent"
          image             = "localhost/vector:e4805b823ae5df1bc19307a22d856627f4e57e91-4f5ab2fb2f82b57a23076b9db90bcd2e335c0f0b"
          name              = "vector"

          volume_mount {
            mount_path = "/var/lib/vector"
            name       = "var-lib-vector"
          }

          volume_mount {
            mount_path = "/etc/vector"
            name       = "etc-vector"
            read_only  = true
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

          port {
            container_port = 8282
            name           = "datadog-agent"
          }
          port {
            container_port = 9598
            name           = "prom-export"
          }

          liveness_probe {
            http_get {
              port = 9598
              path = "/metrics"
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
