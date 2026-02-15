# ------------------------------------------------------------------------------
# RDS Instance Data Sources
# ------------------------------------------------------------------------------

data "aws_db_instance" "this" {
  for_each = var.create_resources ? { for idx, db in var.rds_instances : db.identifier => db } : {}

  db_instance_identifier = each.key
}

# ------------------------------------------------------------------------------
# Aurora Cluster Data Sources
# ------------------------------------------------------------------------------

data "aws_rds_cluster" "this" {
  for_each = var.create_resources ? { for idx, cluster in var.aurora_clusters : cluster.cluster_identifier => cluster } : {}

  cluster_identifier = each.key
}

# ------------------------------------------------------------------------------
# Locals for Database Configuration
# ------------------------------------------------------------------------------

locals {
  # Process RDS instances - detect primary/replica status
  rds_databases = [
    for db in var.rds_instances : {
      name      = db.database_name
      host      = data.aws_db_instance.this[db.identifier].address
      port      = data.aws_db_instance.this[db.identifier].port
      pool_size = db.pool_size
      role = (
        db.role != "auto" ? db.role :
        # Auto-detect: if replicate_source_db is set, it's a replica
        data.aws_db_instance.this[db.identifier].replicate_source_db != "" ? "replica" : "primary"
      )
      identifier = db.identifier
      shard      = db.shard
    }
  ]

  # Process Aurora clusters - create entries for both writer and reader endpoints
  aurora_databases = flatten([
    for cluster in var.aurora_clusters : [
      {
        name       = cluster.database_name
        host       = data.aws_rds_cluster.this[cluster.cluster_identifier].endpoint
        port       = data.aws_rds_cluster.this[cluster.cluster_identifier].port
        pool_size  = cluster.pool_size
        role       = "primary"
        identifier = "${cluster.cluster_identifier}-writer"
        shard      = cluster.shard
      },
      {
        name       = cluster.database_name
        host       = data.aws_rds_cluster.this[cluster.cluster_identifier].reader_endpoint
        port       = data.aws_rds_cluster.this[cluster.cluster_identifier].port
        pool_size  = cluster.pool_size
        role       = "replica"
        identifier = "${cluster.cluster_identifier}-reader"
        shard      = cluster.shard
      }
    ]
  ])

  # Process direct database inputs
  direct_databases = [
    for db in var.databases : {
      name       = db.name
      host       = db.host
      port       = db.port
      pool_size  = db.pool_size
      role       = db.role
      shard      = db.shard
      identifier = "${db.name}-${db.role}-${db.shard}"
    }
  ]

  # Combine all databases
  all_databases = concat(local.direct_databases, local.rds_databases, local.aurora_databases)

  # Group by database name for sharding/load balancing configuration
  databases_by_name = {
    for db in local.all_databases : db.name => db...
  }
}
