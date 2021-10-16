# Variables for a vector install

variable "type" {
  description = "The type of the vector install, whether 'baseline' or 'comparision'"
  type = string
}

variable "sha" {
  description = "The commit SHA from the Vector project under investigation"
  type = string
}

variable "feature_hash" {
  description = "The hash of the feature flags Vector was built with"
  type = string
}

variable "test_name" {
  description = "The name of the soak test"
  type = string
}

variable "vector-toml" {
  description = "The rendered vector.toml for this test"
  type = string
}
