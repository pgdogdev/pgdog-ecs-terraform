test_name = "basic"

databases = [
  {
    name = "postgres"
    host = "mydb.cluster-abc123.us-east-1.rds.amazonaws.com"
    port = 5432
    role = "primary"
  },
  {
    name = "postgres"
    host = "mydb.cluster-ro-abc123.us-east-1.rds.amazonaws.com"
    port = 5432
    role = "replica"
  }
]