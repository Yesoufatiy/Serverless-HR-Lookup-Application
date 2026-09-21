# ─────────────────────────────────────────────────────────────────────────
# Amazon Cognito: User Pool + Managed Login domain + public PKCE client
# ─────────────────────────────────────────────────────────────────────────

resource "aws_cognito_user_pool" "hr_users" {
  name = "hr-lookup-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }
}

# Publishes the Cognito Managed Login pages (hosted sign-in/sign-up UI) at
# https://<domain_prefix>.auth.<region>.amazoncognito.com — this is what the
# browser is redirected to for the "Cognito Managed Login" step.
resource "aws_cognito_user_pool_domain" "hr_domain" {
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.hr_users.id
}

# Public application client: no client secret, so the Authorization Code
# Grant must (and does, via the UI Lambda's JS) use PKCE instead of a secret
# to prove the token exchange request came from the same client that
# started the flow.
resource "aws_cognito_user_pool_client" "hr_ui_client" {
  name         = "hr-lookup-ui-client"
  user_pool_id = aws_cognito_user_pool.hr_users.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  # Both point at the app's own root ("GET /"), which is where the UI
  # Lambda handles the returned authorization code and renders the app.
  callback_urls = [local.hr_api_base_url]
  logout_urls   = [local.hr_api_base_url]

  prevent_user_existence_errors = "ENABLED"
}
