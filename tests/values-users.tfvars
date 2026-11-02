test_name = "users"

databases = [
  {
    name = "postgres"
    host = "mydb.cluster-abc123.us-east-1.rds.amazonaws.com"
    port = 5432
    role = "primary"
  },
  {
    name = "other"
    host = "mydb.cluster-abc123.us-east-1.rds.amazonaws.com"
    port = 5432
    role = "primary"
  }
]

# Same user name on two databases, plus a server password.
users = [
  {
    name      = "app"
    database  = "postgres"
    pool_size = 20
  },
  {
    name                       = "app"
    database                   = "other"
    server_user                = "backend"
    server_password_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789:secret:server"
    read_only                  = true
  }
]
