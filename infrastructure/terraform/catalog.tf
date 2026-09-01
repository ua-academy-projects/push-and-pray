locals {
  catalog = {
    size = {
      gcp = {
        micro  = "e2-micro"
        small  = "e2-small"
        medium = "e2-medium"
      }
      aws = {
        micro  = "t3.micro"
        small  = "t3.small"
        medium = "t3.medium"
      }
    }

    disk_type = {
      gcp = {
        standard = "pd-standard"
        balanced = "pd-balanced"
        ssd      = "pd-ssd"
      }
      aws = {
        standard = "gp2"
        balanced = "gp3"
        ssd      = "io2"
      }
    }

    region = {
      gcp = {
        us-east = "us-east1"
        eu-west = "europe-west1"
      }
      aws = {
        us-east = "us-east-1"
        eu-west = "eu-west-1"
      }
    }

    zone = {
      gcp = {
        us-east = "us-east1-b"
        eu-west = "europe-west1-b"
      }
      aws = {
        us-east = "us-east-1a"
        eu-west = "eu-west-1a"
      }
    }

    os = {
      gcp = {
        "ubuntu-26.04" = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2604-lts-amd64"
        "ubuntu-24.04" = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2404-lts-amd64"
      }
      aws = {
        "ubuntu-26.04" = "ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-amd64-server-*"
        "ubuntu-24.04" = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      }
    }
  }

  public_ip_needs_public_subnet = {
    gcp = false
    aws = true
  }

  supported_clouds = sort(keys(local.catalog.size))
}
