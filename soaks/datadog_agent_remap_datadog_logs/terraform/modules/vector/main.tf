resource "kubernetes_namespace" "vector" {
  metadata {
    name = "vector-${var.type}"
  }
}

resource "kubernetes_config_map" "vector" {
  metadata {
    name = "vector"
    namespace = kubernetes_namespace.vector.metadata[0].name
  }

  data = {
    "vector.toml" = var.vector-toml
  }
}

resource "kubernetes_service" "vector" {
  metadata {
    name = "vector"
    namespace = kubernetes_namespace.vector.metadata[0].name
  }
  spec {
    selector = {
      type = var.type
      soak_test   = kubernetes_deployment.vector.metadata.0.labels.soak_test
      sha         = kubernetes_deployment.vector.metadata.0.labels.sha
      feature_hash = kubernetes_deployment.vector.metadata.0.labels.feature_hash
    }
    session_affinity = "ClientIP"
    port {
      name        = "datadog-agent"
      port        = 8282
      target_port = 8282
    }
    port {
      name        = "prom-export"
      port        = 9090
      target_port = 9090
    }
    type = "LoadBalancer"
  }
}


resource "kubernetes_deployment" "vector" {
  metadata {
    name = "vector"
    namespace = kubernetes_namespace.vector.metadata[0].name
    labels = {
        type = var.type
        soak_test   = var.test_name
        sha         = var.sha
        feature_hash = var.feature_hash
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        type = var.type
        soak_test   = var.test_name
        sha         = var.sha
        feature_hash = var.feature_hash
      }
    }

    template {
      metadata {
        labels = {
        type = var.type
        soak_test   = var.test_name
        sha         = var.sha
        feature_hash = var.feature_hash
        }
        annotations = {
          "prometheus.io/scrape" = true
          "prometheus.io/port" = 9090
          "prometheus.io/path" = "/metrics"
        }
      }

      spec {
        automount_service_account_token = false
        container {
          image_pull_policy = "IfNotPresent"
          image             = "vector:${var.sha}-${var.feature_hash}"
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
              cpu    = "2"
              memory = "512Mi"
            }
            requests = {
              cpu    = "2"
              memory = "512Mi"
            }
          }

          port {
            container_port = 8282
            name           = "datadog-agent"
          }
          port {
            container_port = 9090
            name           = "prom-export"
          }

          liveness_probe {
            http_get {
              port = 9090
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
