# ------------------------------------------------------------------------------
# General
# ------------------------------------------------------------------------------

variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "create_resources" {
  description = "Whether to create AWS resources (set to false for config-only testing)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------------------
# Networking
# ------------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID where ECS tasks will run"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for ECS tasks (should be private subnets)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Additional security group IDs to attach to ECS tasks"
  type        = list(string)
  default     = []
}

variable "nlb_subnet_ids" {
  description = "Subnet IDs for NLB (defaults to var.subnet_ids if not specified)"
  type        = list(string)
  default     = null
}

variable "nlb_internal" {
  description = "Whether the NLB should be internal"
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# RDS Configuration
# ------------------------------------------------------------------------------

variable "databases" {
  description = "Direct database configuration (alternative to rds_instances/aurora_clusters)"
  type = list(object({
    name      = string
    host      = string
    port      = optional(number, 5432)
    pool_size = optional(number)
    role      = optional(string, "primary")
    shard     = optional(number, 0)
  }))
  default = []
}

variable "rds_instances" {
  description = "List of RDS instance identifiers to configure as databases"
  type = list(object({
    identifier    = string
    database_name = string
    role          = optional(string, "auto") # "primary", "replica", or "auto"
    pool_size     = optional(number)         # Optional, uses PgDog default if not set
    shard         = optional(number, 0)
  }))
  default = []
}

variable "aurora_clusters" {
  description = "List of Aurora cluster identifiers to configure as databases"
  type = list(object({
    cluster_identifier = string
    database_name      = string
    pool_size          = optional(number) # Optional, uses PgDog default if not set
    shard              = optional(number, 0)
  }))
  default = []
}

# ------------------------------------------------------------------------------
# PgDog Users Configuration
# ------------------------------------------------------------------------------

variable "users" {
  description = "PgDog users configuration"
  type = list(object({
    name                       = string
    database                   = string
    password_secret_arn        = string
    server_user                = optional(string)
    server_password_secret_arn = optional(string)
    pool_size                  = optional(number, 10)
    pooler_mode                = optional(string, "transaction")
    read_only                  = optional(bool, false)
  }))
}

# ------------------------------------------------------------------------------
# PgDog Configuration
# ------------------------------------------------------------------------------

variable "pgdog" {
  description = "PgDog configuration - mirrors pgdog.toml structure"
  type = object({
    # Container image (not part of pgdog.toml)
    image = optional(string, "ghcr.io/pgdogdev/pgdog:0.1.29")

    # [general] section
    general = optional(object({
      port                      = optional(number, 6432)
      metrics_port              = optional(number, 9090)
      healthcheck_port          = optional(number)
      workers                   = optional(number, 4)
      default_pool_size         = optional(number, 10)
      min_pool_size             = optional(number, 1)
      pooler_mode               = optional(string, "transaction")
      load_balancing_strategy   = optional(string, "round_robin")
      read_write_strategy       = optional(string, "conservative")
      read_write_split          = optional(string)
      healthcheck_interval      = optional(number, 30000)
      idle_healthcheck_interval = optional(number, 30000)
      idle_healthcheck_delay    = optional(number, 5000)
      healthcheck_timeout       = optional(number, 5000)
      ban_timeout               = optional(number)
      connect_timeout           = optional(number, 5000)
      checkout_timeout          = optional(number, 5000)
      query_timeout             = optional(number)
      idle_timeout              = optional(number)
      client_idle_timeout       = optional(number)
      rollback_timeout          = optional(number, 5000)
      shutdown_timeout          = optional(number, 60000)
      server_lifetime           = optional(number, 86400000)
      auth_type                 = optional(string, "scram")
      passthrough_auth          = optional(string, "disabled")
      prepared_statements       = optional(string, "extended")
      query_parser              = optional(string, "auto")
      log_connections           = optional(bool, true)
      log_disconnections        = optional(bool, true)
      openmetrics_namespace     = optional(string, "pgdog_")
      mirror_queue              = optional(number, 128)
      mirror_exposure           = optional(number, 1.0)
      dry_run                   = optional(bool, false)
      cross_shard_disabled      = optional(bool, false)
    }), {})

    # [tls] settings (part of [general] in pgdog.toml)
    tls = optional(object({
      certificate           = optional(string)
      private_key           = optional(string)
      client_required       = optional(bool, false)
      verify                = optional(string, "prefer")
      server_ca_certificate = optional(string)
    }))

    # [tcp] section
    tcp = optional(object({
      keepalive = optional(bool)
      time      = optional(number)
      interval  = optional(number)
      retries   = optional(number)
    }))

    # [memory] section
    memory = optional(object({
      net_buffer     = optional(number)
      message_buffer = optional(number)
      stack_size     = optional(number)
    }))

    # [admin] section
    admin = optional(object({
      password = optional(string)
    }))

    # [query_stats] section
    query_stats = optional(object({
      enabled              = optional(bool, false)
      max_entries          = optional(number, 10000)
      query_plan_threshold = optional(number, 250)
      query_plans_cache    = optional(number, 100)
      query_plan_max_age   = optional(number, 15000)
      max_errors           = optional(number, 100)
      max_error_age        = optional(number, 300000)
    }))

    # [rewrite] section
    rewrite = optional(object({
      enabled       = optional(bool, false)
      shard_key     = optional(string, "error")
      split_inserts = optional(string, "error")
      primary_key   = optional(string, "ignore")
    }))

    # [[sharded_tables]] section
    sharded_tables = optional(list(object({
      database  = string
      name      = optional(string)
      column    = string
      data_type = string
    })), [])

    # [[sharded_schemas]] section
    sharded_schemas = optional(list(object({
      database = string
      name     = optional(string)
      shard    = number
    })), [])

    # [[sharded_mappings]] section
    sharded_mappings = optional(list(object({
      database = string
      column   = string
      kind     = string # "list" or "range"
      shard    = number
      values   = optional(list(string))
      start    = optional(number)
      end      = optional(number)
    })), [])

    # [[omnisharded_tables]] section
    omnisharded_tables = optional(list(object({
      database = string
      tables   = list(string)
      sticky   = optional(bool)
    })), [])

    # [[mirroring]] section
    mirrors = optional(list(object({
      source_db      = string
      destination_db = string
      queue_depth    = optional(number)
      exposure       = optional(number)
    })), [])
  })

  default = {}
}

# ------------------------------------------------------------------------------
# ECS Configuration
# ------------------------------------------------------------------------------

variable "ecs_cluster_arn" {
  description = "Existing ECS cluster ARN (if not provided, a new cluster will be created)"
  type        = string
  default     = null
}

variable "task_cpu" {
  description = "CPU units for the Fargate task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 1024
}

variable "task_memory" {
  description = "Memory in MB for the Fargate task"
  type        = number
  default     = 2048
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Minimum number of ECS tasks for auto-scaling"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of ECS tasks for auto-scaling"
  type        = number
  default     = 10
}

variable "cpu_target_value" {
  description = "Target CPU utilization percentage for auto-scaling"
  type        = number
  default     = 70
}

variable "memory_target_value" {
  description = "Target memory utilization percentage for auto-scaling"
  type        = number
  default     = 70
}

variable "scale_in_cooldown" {
  description = "Scale in cooldown in seconds"
  type        = number
  default     = 300
}

variable "scale_out_cooldown" {
  description = "Scale out cooldown in seconds"
  type        = number
  default     = 60
}

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# ------------------------------------------------------------------------------
# Health Check
# ------------------------------------------------------------------------------

variable "health_check_grace_period" {
  description = "Seconds to wait before starting health checks on a new task"
  type        = number
  default     = 60
}

variable "deregistration_delay" {
  description = "Seconds to wait before deregistering a target from the NLB"
  type        = number
  default     = 30
}
