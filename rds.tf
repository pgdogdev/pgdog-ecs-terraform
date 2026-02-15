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
  # Build Aurora instance config map first (needed for data source for_each)
  aurora_instance_configs = var.create_resources ? merge([
    for cluster in var.aurora_clusters : {
      for member in data.aws_rds_cluster.this[cluster.cluster_identifier].cluster_members :
      member => {
        cluster_identifier = cluster.cluster_identifier
        database_name      = cluster.database_name
        pool_size          = cluster.pool_size
        shard              = cluster.shard
      }
    }
  ]...) : {}
}

# Get individual Aurora instances
data "aws_db_instance" "aurora" {
  for_each = local.aurora_instance_configs

  db_instance_identifier = each.key
}

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

  # Process Aurora clusters - use individual instance endpoints
  # Role is "auto" - PgDog detects primary/replica via LSN checking
  aurora_databases = var.create_resources ? [
    for instance_id, instance in data.aws_db_instance.aurora : {
      name       = local.aurora_instance_configs[instance_id].database_name
      host       = instance.address
      port       = instance.port
      pool_size  = local.aurora_instance_configs[instance_id].pool_size
      role       = "auto"
      identifier = instance_id
      shard      = local.aurora_instance_configs[instance_id].shard
    }
  ] : []

  # Enable LSN checking when Aurora clusters are configured
  has_aurora = length(var.aurora_clusters) > 0

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
