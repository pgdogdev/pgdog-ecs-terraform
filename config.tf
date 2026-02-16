# ------------------------------------------------------------------------------
# PgDog Configuration Generation
# ------------------------------------------------------------------------------

locals {
  # Shorthand references - defaults are already set in variable definition via optional()
  pgdog_image   = var.pgdog.image
  pgdog_general = var.pgdog.general

  pgdog_tls              = var.pgdog.tls
  pgdog_tcp              = var.pgdog.tcp
  pgdog_memory           = var.pgdog.memory
  pgdog_admin            = var.pgdog.admin
  pgdog_query_stats      = var.pgdog.query_stats
  pgdog_rewrite          = var.pgdog.rewrite
  pgdog_sharded_tables   = coalesce(var.pgdog.sharded_tables, [])
  pgdog_sharded_schemas  = coalesce(var.pgdog.sharded_schemas, [])
  pgdog_sharded_mappings = coalesce(var.pgdog.sharded_mappings, [])
  pgdog_omnisharded      = coalesce(var.pgdog.omnisharded_tables, [])
  pgdog_mirrors          = coalesce(var.pgdog.mirrors, [])

  # Generate [[databases]] blocks
  databases_toml = join("\n", [
    for db in local.all_databases : join("\n", compact([
      "[[databases]]",
      "name = \"${db.name}\"",
      "host = \"${db.host}\"",
      "port = ${db.port}",
      db.pool_size != null ? "pool_size = ${db.pool_size}" : "",
      "role = \"${db.role}\"",
      "shard = ${db.shard}",
      "",
    ]))
  ])

  # Generate [[sharded_tables]] blocks
  sharded_tables_toml = join("\n", [
    for table in local.pgdog_sharded_tables : <<-EOT
[[sharded_tables]]
database = "${table.database}"
${table.name != null ? "name = \"${table.name}\"" : ""}
column = "${table.column}"
data_type = "${table.data_type}"
EOT
  ])

  # Generate [[sharded_schemas]] blocks
  sharded_schemas_toml = join("\n", [
    for schema in local.pgdog_sharded_schemas : <<-EOT
[[sharded_schemas]]
database = "${schema.database}"
${schema.name != null ? "name = \"${schema.name}\"" : ""}
${schema.shard != null ? "shard = ${schema.shard}" : ""}
${schema.all == true ? "all = true" : ""}
EOT
  ])

  # Generate [[sharded_mappings]] blocks
  sharded_mappings_toml = join("\n", [
    for mapping in local.pgdog_sharded_mappings : <<-EOT
[[sharded_mappings]]
database = "${mapping.database}"
column = "${mapping.column}"
kind = "${mapping.kind}"
shard = ${mapping.shard}
${mapping.values != null ? "values = [${join(", ", [for v in mapping.values : can(tonumber(v)) ? v : "\"${v}\""])}]" : ""}
${mapping.start != null ? "start = ${mapping.start}" : ""}
${mapping.end != null ? "end = ${mapping.end}" : ""}
EOT
  ])

  # Generate [[omnisharded_tables]] blocks
  omnisharded_tables_toml = join("\n", [
    for table in local.pgdog_omnisharded : <<-EOT
[[omnisharded_tables]]
database = "${table.database}"
tables = [${join(", ", [for t in table.tables : "\"${t}\""])}]
${table.sticky != null ? "sticky = ${table.sticky}" : ""}
EOT
  ])

  # Generate [[mirroring]] blocks
  mirrors_toml = join("\n", [
    for mirror in local.pgdog_mirrors : <<-EOT
[[mirroring]]
source_db = "${mirror.source_db}"
destination_db = "${mirror.destination_db}"
${mirror.queue_depth != null ? "queue_depth = ${mirror.queue_depth}" : ""}
${mirror.exposure != null ? "exposure = ${mirror.exposure}" : ""}
EOT
  ])

  # Generate [tcp] section
  has_tcp_settings = local.pgdog_tcp != null && anytrue([
    try(local.pgdog_tcp.keepalive, null) != null,
    try(local.pgdog_tcp.time, null) != null,
    try(local.pgdog_tcp.interval, null) != null,
    try(local.pgdog_tcp.retries, null) != null,
    try(local.pgdog_tcp.user_timeout, null) != null
  ])

  tcp_toml = local.has_tcp_settings ? join("\n", compact([
    "[tcp]",
    try(local.pgdog_tcp.keepalive, null) != null ? "keepalive = ${local.pgdog_tcp.keepalive}" : "",
    try(local.pgdog_tcp.time, null) != null ? "time = ${local.pgdog_tcp.time}" : "",
    try(local.pgdog_tcp.interval, null) != null ? "interval = ${local.pgdog_tcp.interval}" : "",
    try(local.pgdog_tcp.retries, null) != null ? "retries = ${local.pgdog_tcp.retries}" : "",
    try(local.pgdog_tcp.user_timeout, null) != null ? "user_timeout = ${local.pgdog_tcp.user_timeout}" : "",
  ])) : ""

  # Generate [memory] section
  has_memory_settings = local.pgdog_memory != null && anytrue([
    try(local.pgdog_memory.net_buffer, null) != null,
    try(local.pgdog_memory.message_buffer, null) != null,
    try(local.pgdog_memory.stack_size, null) != null
  ])

  memory_toml = local.has_memory_settings ? join("\n", compact([
    "[memory]",
    try(local.pgdog_memory.net_buffer, null) != null ? "net_buffer = ${local.pgdog_memory.net_buffer}" : "",
    try(local.pgdog_memory.message_buffer, null) != null ? "message_buffer = ${local.pgdog_memory.message_buffer}" : "",
    try(local.pgdog_memory.stack_size, null) != null ? "stack_size = ${local.pgdog_memory.stack_size}" : "",
  ])) : ""

  # Generate [admin] section
  has_admin_settings = local.pgdog_admin != null && anytrue([
    try(local.pgdog_admin.name, null) != null,
    try(local.pgdog_admin.user, null) != null,
    try(local.pgdog_admin.password, null) != null
  ])

  admin_toml = local.has_admin_settings ? join("\n", compact([
    "[admin]",
    try(local.pgdog_admin.name, null) != null ? "name = \"${local.pgdog_admin.name}\"" : "",
    try(local.pgdog_admin.user, null) != null ? "user = \"${local.pgdog_admin.user}\"" : "",
    try(local.pgdog_admin.password, null) != null ? "password = \"${local.pgdog_admin.password}\"" : "",
  ])) : ""

  # Generate [query_stats] section
  query_stats_toml = try(local.pgdog_query_stats.enabled, false) ? join("\n", [
    "[query_stats]",
    "enabled = true",
    "max_entries = ${try(local.pgdog_query_stats.max_entries, 10000)}",
    "query_plan_threshold = ${try(local.pgdog_query_stats.query_plan_threshold, 250)}",
    "query_plans_cache = ${try(local.pgdog_query_stats.query_plans_cache, 100)}",
    "query_plan_max_age = ${try(local.pgdog_query_stats.query_plan_max_age, 15000)}",
    "max_errors = ${try(local.pgdog_query_stats.max_errors, 100)}",
    "max_error_age = ${try(local.pgdog_query_stats.max_error_age, 300000)}",
  ]) : ""

  # Generate [rewrite] section
  rewrite_toml = try(local.pgdog_rewrite.enabled, false) ? join("\n", [
    "[rewrite]",
    "enabled = true",
    "shard_key = \"${try(local.pgdog_rewrite.shard_key, "error")}\"",
    "split_inserts = \"${try(local.pgdog_rewrite.split_inserts, "error")}\"",
    "primary_key = \"${try(local.pgdog_rewrite.primary_key, "ignore")}\"",
  ]) : ""

  # TLS settings - use file paths when tls_mode is enabled, otherwise use pgdog.tls config
  tls_enabled               = var.tls_mode != "disabled"
  tls_certificate           = local.tls_enabled ? "/etc/pgdog/server.crt" : try(local.pgdog_tls.certificate, null)
  tls_private_key           = local.tls_enabled ? "/etc/pgdog/server.key" : try(local.pgdog_tls.private_key, null)
  tls_client_required       = try(local.pgdog_tls.client_required, false)
  tls_verify                = try(local.pgdog_tls.verify, "prefer")
  tls_server_ca_certificate = try(local.pgdog_tls.server_ca_certificate, null)

  # Shorthand
  g = local.pgdog_general

  # Generate pgdog.toml content - output all settings explicitly
  pgdog_toml = join("\n", compact([
    "[general]",
    "port = ${local.g.port}",
    local.g.healthcheck_port != null ? "healthcheck_port = ${local.g.healthcheck_port}" : "",
    local.g.openmetrics_port != null ? "openmetrics_port = ${local.g.openmetrics_port}" : "",
    local.g.openmetrics_namespace != null ? "openmetrics_namespace = \"${local.g.openmetrics_namespace}\"" : "",
    "workers = ${local.g.workers}",
    "default_pool_size = ${local.g.default_pool_size}",
    "min_pool_size = ${local.g.min_pool_size}",
    "pooler_mode = \"${local.g.pooler_mode}\"",
    "load_balancing_strategy = \"${local.g.load_balancing_strategy}\"",
    "read_write_split = \"${local.g.read_write_split}\"",
    "healthcheck_interval = ${local.g.healthcheck_interval}",
    "idle_healthcheck_interval = ${local.g.idle_healthcheck_interval}",
    "idle_healthcheck_delay = ${local.g.idle_healthcheck_delay}",
    "connection_recovery = \"${local.g.connection_recovery}\"",
    "client_connection_recovery = \"${local.g.client_connection_recovery}\"",
    "rollback_timeout = ${local.g.rollback_timeout}",
    "ban_timeout = ${local.g.ban_timeout}",
    "shutdown_timeout = ${local.g.shutdown_timeout}",
    local.g.shutdown_termination_timeout != null ? "shutdown_termination_timeout = ${local.g.shutdown_termination_timeout}" : "",
    local.g.query_timeout != null ? "query_timeout = ${local.g.query_timeout}" : "",
    "connect_timeout = ${local.g.connect_timeout}",
    "connect_attempts = ${local.g.connect_attempts}",
    "connect_attempt_delay = ${local.g.connect_attempt_delay}",
    "checkout_timeout = ${local.g.checkout_timeout}",
    "idle_timeout = ${local.g.idle_timeout}",
    local.g.client_idle_timeout != null ? "client_idle_timeout = ${local.g.client_idle_timeout}" : "",
    "client_login_timeout = ${local.g.client_login_timeout}",
    "server_lifetime = ${local.g.server_lifetime}",
    local.tls_certificate != null ? "tls_certificate = \"${local.tls_certificate}\"" : "",
    local.tls_private_key != null ? "tls_private_key = \"${local.tls_private_key}\"" : "",
    "tls_client_required = ${local.tls_client_required}",
    "tls_verify = \"${local.tls_verify}\"",
    local.tls_server_ca_certificate != null ? "tls_server_ca_certificate = \"${local.tls_server_ca_certificate}\"" : "",
    "auth_type = \"${local.g.auth_type}\"",
    "passthrough_auth = \"${local.g.passthrough_auth}\"",
    "prepared_statements = \"${local.g.prepared_statements}\"",
    local.g.prepared_statements_limit != null ? "prepared_statements_limit = ${local.g.prepared_statements_limit}" : "",
    "query_parser = \"${local.g.query_parser}\"",
    "query_cache_limit = ${local.g.query_cache_limit}",
    "cross_shard_disabled = ${local.g.cross_shard_disabled}",
    "system_catalogs = \"${local.g.system_catalogs}\"",
    "omnisharded_sticky = ${local.g.omnisharded_sticky}",
    "mirror_queue = ${local.g.mirror_queue}",
    "mirror_exposure = ${local.g.mirror_exposure}",
    "dry_run = ${local.g.dry_run}",
    "two_phase_commit = ${local.g.two_phase_commit}",
    "two_phase_commit_auto = ${local.g.two_phase_commit_auto}",
    local.g.pub_sub_channel_size != null ? "pub_sub_channel_size = ${local.g.pub_sub_channel_size}" : "",
    "resharding_copy_format = \"${local.g.resharding_copy_format}\"",
    local.g.reload_schema_on_ddl != null ? "reload_schema_on_ddl = ${local.g.reload_schema_on_ddl}" : "",
    "log_connections = ${local.g.log_connections}",
    "log_disconnections = ${local.g.log_disconnections}",
    "stats_period = ${local.g.stats_period}",
    local.g.dns_ttl != null ? "dns_ttl = ${local.g.dns_ttl}" : "",
    local.g.lsn_check_delay != null || local.has_aurora ? "lsn_check_delay = ${coalesce(local.g.lsn_check_delay, 0)}" : "",
    local.g.lsn_check_interval != null || local.has_aurora ? "lsn_check_interval = ${coalesce(local.g.lsn_check_interval, 1000)}" : "",
    local.g.lsn_check_timeout != null ? "lsn_check_timeout = ${local.g.lsn_check_timeout}" : "",
    "",
    local.databases_toml,
    local.mirrors_toml,
    local.sharded_tables_toml,
    local.sharded_schemas_toml,
    local.sharded_mappings_toml,
    local.omnisharded_tables_toml,
    local.tcp_toml,
    local.memory_toml,
    local.admin_toml,
    local.query_stats_toml,
    local.rewrite_toml,
  ]))

  # Generate users.toml content with actual passwords from Secrets Manager
  users_toml = join("\n", [
    for user in var.users : join("\n", compact([
      "[[users]]",
      "name = \"${user.name}\"",
      "database = \"${user.database}\"",
      "password = \"${data.aws_secretsmanager_secret_version.user_passwords[user.name].secret_string}\"",
      user.pool_size != null ? "pool_size = ${user.pool_size}" : "",
      user.pooler_mode != null ? "pooler_mode = \"${user.pooler_mode}\"" : "",
      user.read_only == true ? "read_only = true" : "",
      user.server_user != null ? "server_user = \"${user.server_user}\"" : "",
      user.server_password_secret_arn != null ? "server_password = \"${data.aws_secretsmanager_secret_version.server_passwords[user.name].secret_string}\"" : "",
      "",
    ]))
  ])

  # Config hash for triggering rolling deployments when config changes
  config_hash = sha256("${local.pgdog_toml}${local.users_toml}")

  # For validation output, mask passwords
  users_toml_masked = join("\n", [
    for user in var.users : join("\n", compact([
      "[[users]]",
      "name = \"${user.name}\"",
      "database = \"${user.database}\"",
      "password = \"REDACTED\"",
      user.pool_size != null ? "pool_size = ${user.pool_size}" : "",
      user.pooler_mode != null ? "pooler_mode = \"${user.pooler_mode}\"" : "",
      user.read_only == true ? "read_only = true" : "",
      user.server_user != null ? "server_user = \"${user.server_user}\"" : "",
      user.server_password_secret_arn != null ? "server_password = \"REDACTED\"" : "",
      "",
    ]))
  ])
}

# Fetch user passwords from Secrets Manager
data "aws_secretsmanager_secret_version" "user_passwords" {
  for_each  = var.create_resources ? { for user in var.users : user.name => user.password_secret_arn } : {}
  secret_id = each.value
}

# Fetch server passwords from Secrets Manager (if specified)
data "aws_secretsmanager_secret_version" "server_passwords" {
  for_each  = var.create_resources ? { for user in var.users : user.name => user.server_password_secret_arn if user.server_password_secret_arn != null } : {}
  secret_id = each.value
}

# ------------------------------------------------------------------------------
# OTEL Collector Configuration (for CloudWatch metrics export)
# ------------------------------------------------------------------------------

locals {
  # Use configured port or default 9090 for metrics
  metrics_port = coalesce(local.pgdog_general.openmetrics_port, 9090)

  otel_config = var.create_resources && var.export_metrics_to_cloudwatch ? yamlencode({
    receivers = {
      prometheus = {
        config = {
          scrape_configs = [
            {
              job_name         = "pgdog"
              scrape_interval  = "${var.metrics_collection_interval}s"
              static_configs   = [{ targets = ["localhost:${local.metrics_port}"] }]
              metrics_path     = "/metrics"
              honor_labels     = true
              honor_timestamps = true
            }
          ]
        }
      }
    }
    processors = {
      batch = {
        timeout = "60s"
      }
    }
    exporters = {
      awsemf = {
        namespace               = var.cloudwatch_metrics_namespace
        region                  = data.aws_region.current[0].id
        log_group_name          = "/aws/ecs/${var.name}-pgdog/metrics"
        log_stream_name         = "otel-metrics"
        dimension_rollup_option = "NoDimensionRollup"
        resource_to_telemetry_conversion = {
          enabled = true
        }
      }
    }
    service = {
      pipelines = {
        metrics = {
          receivers  = ["prometheus"]
          processors = ["batch"]
          exporters  = ["awsemf"]
        }
      }
    }
  }) : ""
}
