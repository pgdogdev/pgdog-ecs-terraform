test_name = "passthrough"

databases = [
  {
    name = "postgres"
    host = "mydb.cluster-abc123.us-east-1.rds.amazonaws.com"
    port = 5432
    role = "primary"
  }
]

# No users: authentication is passed through to the server.
# users.toml must still be non-empty (Secrets Manager rejects empty strings).
users = []

pgdog = {
  general = {
    passthrough_auth = "enabled"
  }
}
