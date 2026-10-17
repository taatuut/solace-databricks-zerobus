terraform {
  required_version = ">= 1.5"

  required_providers {
    solacecloud = {
      source = "solaceproducts/solacecloud"
      # BETA provider -- pin to the exact version shown by `terraform init`
      # the first time you run it (check
      # https://registry.terraform.io/providers/SolaceProducts/solacecloud/latest
      # for the current release). Deliberately unpinned here so the first
      # `terraform init` tells you what's actually current.
    }
  }
}

provider "solacecloud" {
  base_url  = var.solace_cloud_api_base_url
  api_token = var.solace_cloud_api_token
}

# If this demo needs services across more than one Solace Cloud
# organization (different API token AND possibly different base_url
# per org), duplicate the provider block above with an `alias`, and add
# `provider = solacecloud.<alias>` to the matching resource(s) in
# main.tf. Each org needs its own pair of `*_api_token`/`*_base_url`
# variables -- don't assume they share either value.
