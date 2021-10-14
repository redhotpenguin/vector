resource "kubernetes_namespace" "lading" {
  metadata {
    name = "lading"
  }
}

resource "kubernetes_config_map" "lading" {
  metadata {
    name      = "lading"
    namespace = kubernetes_namespace.lading.metadata[0].name
  }

  data = {
    "http_gen.toml" =  "${file("${path.module}/http_gen.toml")}"
    "http_blackhole.toml" = "${file("${path.module}/http_blackhole.toml")}"
  }
}

resource "kubernetes_service" "http-blackhole" {
  metadata {
    name      = "http-blackhole"
    namespace = kubernetes_namespace.lading.metadata[0].name
  }
  spec {
    selector = {
      app = "http-blackhole"
    }
    session_affinity = "ClientIP"
    port {
      name        = "datadog-agent"
      port        = 8080
      target_port = 8080
    }
    port {
      name        = "prom-export"
      port        = 9090
      target_port = 9090
    }
    type = "LoadBalancer"
  }
}


resource "kubernetes_deployment" "http-blackhole" {
  metadata {
    name      = "http-blackhole"
    namespace = kubernetes_namespace.lading.metadata[0].name
    labels = {
      app = "http-blackhole"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "http-blackhole"
      }
    }

    template {
      metadata {
        labels = {
          app = "http-blackhole"
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
          image             = "ghcr.io/blt/lading:0.5.0"
          name              = "http-blackhole"
          command = ["/http_blackhole"]

          volume_mount {
            mount_path = "/etc/lading"
            name       = "etc-lading"
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
            container_port = 8080
            name           = "listen"
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
          name = "etc-lading"
          config_map {
            name = kubernetes_config_map.lading.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "http-gen" {
  metadata {
    name      = "http-gen"
    namespace = kubernetes_namespace.lading.metadata[0].name
  }
  spec {
    selector = {
      app = "http-gen"
    }
    session_affinity = "ClientIP"
    port {
      name        = "datadog-agent"
      port        = 8080
      target_port = 8080
    }
    port {
      name        = "prom-export"
      port        = 9090
      target_port = 9090
    }
    type = "LoadBalancer"
  }
}


resource "kubernetes_deployment" "http-gen" {
  metadata {
    name      = "http-gen"
    namespace = kubernetes_namespace.lading.metadata[0].name
    labels = {
      app = "http-gen"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "http-gen"
      }
    }

    template {
      metadata {
        labels = {
          app = "http-gen"
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
          image             = "ghcr.io/blt/lading:0.5.0"
          name              = "http-gen"
          command = ["/http_gen"]

          volume_mount {
            mount_path = "/etc/lading"
            name       = "etc-lading"
            read_only  = true
          }

          resources {
            limits = {
              cpu    = "1"
              memory = "512Mi"
            }
            requests = {
              cpu    = "1"
              memory = "512Mi"
            }
          }

          port {
            container_port = 8080
            name           = "listen"
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
          name = "etc-lading"
          config_map {
            name = kubernetes_config_map.lading.metadata[0].name
          }
        }
      }
    }
  }
}
