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
shard = ${schema.shard}
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
${mapping.values != null ? "values = [${join(", ", [for v in mapping.values : "\"${v}\""])}]" : ""}
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
    try(local.pgdog_tcp.retries, null) != null
  ])

  tcp_toml = local.has_tcp_settings ? join("\n", compact([
    "[tcp]",
    try(local.pgdog_tcp.keepalive, null) != null ? "keepalive = ${local.pgdog_tcp.keepalive}" : "",
    try(local.pgdog_tcp.time, null) != null ? "time = ${local.pgdog_tcp.time}" : "",
    try(local.pgdog_tcp.interval, null) != null ? "interval = ${local.pgdog_tcp.interval}" : "",
    try(local.pgdog_tcp.retries, null) != null ? "retries = ${local.pgdog_tcp.retries}" : "",
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
  admin_toml = try(local.pgdog_admin.password, null) != null ? "[admin]\npassword = \"${local.pgdog_admin.password}\"" : ""

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

  # TLS settings
  tls_certificate           = try(local.pgdog_tls.certificate, null)
  tls_private_key           = try(local.pgdog_tls.private_key, null)
  tls_client_required       = try(local.pgdog_tls.client_required, false)
  tls_verify                = try(local.pgdog_tls.verify, "prefer")
  tls_server_ca_certificate = try(local.pgdog_tls.server_ca_certificate, null)

  # Generate pgdog.toml content
  pgdog_toml = join("\n", compact([
    "[general]",
    "port                      = ${local.pgdog_general.port}",
    "workers                   = ${local.pgdog_general.workers}",
    "default_pool_size         = ${local.pgdog_general.default_pool_size}",
    "min_pool_size             = ${local.pgdog_general.min_pool_size}",
    "pooler_mode               = \"${local.pgdog_general.pooler_mode}\"",
    local.pgdog_general.healthcheck_port != null ? "healthcheck_port          = ${local.pgdog_general.healthcheck_port}" : "",
    "healthcheck_interval      = ${local.pgdog_general.healthcheck_interval}",
    "idle_healthcheck_interval = ${local.pgdog_general.idle_healthcheck_interval}",
    "idle_healthcheck_delay    = ${local.pgdog_general.idle_healthcheck_delay}",
    "healthcheck_timeout       = ${local.pgdog_general.healthcheck_timeout}",
    local.pgdog_general.ban_timeout != null ? "ban_timeout               = ${local.pgdog_general.ban_timeout}" : "",
    "rollback_timeout          = ${local.pgdog_general.rollback_timeout}",
    "load_balancing_strategy   = \"${local.pgdog_general.load_balancing_strategy}\"",
    "read_write_strategy       = \"${local.pgdog_general.read_write_strategy}\"",
    local.pgdog_general.read_write_split != null ? "read_write_split          = \"${local.pgdog_general.read_write_split}\"" : "",
    local.tls_certificate != null ? "tls_certificate           = \"${local.tls_certificate}\"" : "",
    local.tls_private_key != null ? "tls_private_key           = \"${local.tls_private_key}\"" : "",
    "tls_client_required       = ${local.tls_client_required}",
    "tls_verify                = \"${local.tls_verify}\"",
    local.tls_server_ca_certificate != null ? "tls_server_ca_certificate = \"${local.tls_server_ca_certificate}\"" : "",
    "shutdown_timeout          = ${local.pgdog_general.shutdown_timeout}",
    "prepared_statements       = \"${local.pgdog_general.prepared_statements}\"",
    "query_parser              = \"${local.pgdog_general.query_parser}\"",
    "passthrough_auth          = \"${local.pgdog_general.passthrough_auth}\"",
    "connect_timeout           = ${local.pgdog_general.connect_timeout}",
    "checkout_timeout          = ${local.pgdog_general.checkout_timeout}",
    local.pgdog_general.query_timeout != null ? "query_timeout             = ${local.pgdog_general.query_timeout}" : "",
    local.pgdog_general.idle_timeout != null ? "idle_timeout              = ${local.pgdog_general.idle_timeout}" : "",
    local.pgdog_general.client_idle_timeout != null ? "client_idle_timeout       = ${local.pgdog_general.client_idle_timeout}" : "",
    "dry_run                   = ${local.pgdog_general.dry_run}",
    "mirror_queue              = ${local.pgdog_general.mirror_queue}",
    "mirror_exposure           = ${local.pgdog_general.mirror_exposure}",
    "auth_type                 = \"${local.pgdog_general.auth_type}\"",
    "cross_shard_disabled      = ${local.pgdog_general.cross_shard_disabled}",
    "openmetrics_port          = ${local.pgdog_general.metrics_port}",
    "openmetrics_namespace     = \"${local.pgdog_general.openmetrics_namespace}\"",
    "server_lifetime           = ${local.pgdog_general.server_lifetime}",
    "log_connections           = ${local.pgdog_general.log_connections}",
    "log_disconnections        = ${local.pgdog_general.log_disconnections}",
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

  # Generate users.toml content with secret ARN placeholders
  # Init container will replace {{SECRET:arn}} with actual values
  users_toml = join("\n", [
    for user in var.users : join("\n", compact([
      "[[users]]",
      "name = \"${user.name}\"",
      "database = \"${user.database}\"",
      "password = \"{{SECRET:${user.password_secret_arn}}}\"",
      user.pool_size != null ? "pool_size = ${user.pool_size}" : "",
      user.pooler_mode != null ? "pooler_mode = \"${user.pooler_mode}\"" : "",
      user.read_only == true ? "read_only = true" : "",
      user.server_user != null ? "server_user = \"${user.server_user}\"" : "",
      user.server_password_secret_arn != null ? "server_password = \"{{SECRET:${user.server_password_secret_arn}}}\"" : "",
      "",
    ]))
  ])
}
