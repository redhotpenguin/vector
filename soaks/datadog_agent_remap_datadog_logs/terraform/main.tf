terraform {
  required_providers {
    kubernetes = {
      version = "~> 2.5.0"
      source  = "hashicorp/kubernetes"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}


module "baseline" {
  source = "./modules/vector"
  type = "baseline"
  sha = "e4805b823ae5df1bc19307a22d856627f4e57e91"
  feature_hash = "4f5ab2fb2f82b57a23076b9db90bcd2e335c0f0b"
  test_name = "datadog_agent_remap_datadog_logs"
  vector-toml = "${file("${path.module}/vector.toml")}"
}
module "baseline-http-blackhole" {
  source = "./modules/lading_http_blackhole"
  type = module.baseline.type
  namespace = module.baseline.namespace
  http-blackhole-toml = "${file("${path.module}/http_blackhole.toml")}"
}
module "baseline-http-gen" {
  source = "./modules/lading_http_gen"
  type = module.baseline.type
  namespace = module.baseline.namespace
  http-gen-toml = "${file("${path.module}/http_gen.toml")}"
}

module "comparison" {
  source = "./modules/vector"
  type = "comparison"
  sha = "e4805b823ae5df1bc19307a22d856627f4e57e91"
  feature_hash = "4f5ab2fb2f82b57a23076b9db90bcd2e335c0f0b"
  test_name = "datadog_agent_remap_datadog_logs"
  vector-toml = "${file("${path.module}/vector.toml")}"
}
module "comparison-http-blackhole" {
  source = "./modules/lading_http_blackhole"
  type = module.comparison.type
  namespace = module.comparison.namespace
  http-blackhole-toml = "${file("${path.module}/http_blackhole.toml")}"
}
module "comparison-http-gen" {
  source = "./modules/lading_http_gen"
  type = module.comparison.type
  namespace = module.comparison.namespace
  http-gen-toml = "${file("${path.module}/http_gen.toml")}"
}
