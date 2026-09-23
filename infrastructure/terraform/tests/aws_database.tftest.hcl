mock_provider "aws" {}
mock_provider "random" {}

variables {
  config = merge(jsondecode(file("../../project-config.example.json")), {
    default_cloud = "aws"
  })
  vpc_id = "vpc-00000000000000001"
  database_subnet_ids = [
    "subnet-00000000000000001",
    "subnet-00000000000000002",
  ]
  client_security_group_ids = {
    infra   = "sg-00000000000000001"
    history = "sg-00000000000000002"
  }
  password_secret_arn = "arn:aws:secretsmanager:us-east-1:000000000000:secret:example-db-password"
}

run "private_rds_postgresql" {
  command = plan

  module {
    source = "./modules/aws_database"
  }

  assert {
    condition = (
      aws_db_instance.main.publicly_accessible == false &&
      aws_db_instance.main.storage_encrypted == true &&
      length(aws_db_subnet_group.main.subnet_ids) == 2
    )
    error_message = "RDS must be encrypted, private, and attached to both database subnets."
  }

  assert {
    condition     = toset(keys(aws_vpc_security_group_ingress_rule.clients)) == toset(["infra", "history"])
    error_message = "Only infra and History security groups may connect to PostgreSQL."
  }
}
