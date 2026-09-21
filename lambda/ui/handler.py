import os

COGNITO_DOMAIN = os.environ["COGNITO_DOMAIN"]
COGNITO_CLIENT_ID = os.environ["COGNITO_CLIENT_ID"]
REDIRECT_URI = os.environ["REDIRECT_URI"]

PAGE_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>HR Employee Lookup</title>
<style>
  body { font-family: Arial, sans-serif; max-width: 480px; margin: 60px auto; padding: 0 16px; }
  h1 { font-size: 1.4rem; }
  #topbar { display: flex; justify-content: space-between; align-items: center; }
  #search-form { display: flex; gap: 8px; margin-bottom: 16px; }
  #search-form input { flex: 1; font-size: 1rem; padding: 8px; }
  button { font-size: 1rem; padding: 8px 12px; cursor: pointer; }
  dl { border: 1px solid #ccc; border-radius: 6px; padding: 4px 16px; }
  dt { font-weight: bold; margin-top: 8px; }
  #error { color: #b00020; }
</style>
</head>
<body>
  <div id="topbar">
    <h1>HR Employee Lookup</h1>
    <button id="logout-btn" style="display:none">Log out</button>
  </div>

  <div id="login-view">
    <p>Please sign in to look up employee records.</p>
    <button id="login-btn">Log in</button>
  </div>

  <div id="app-view" style="display:none">
    <form id="search-form">
      <input id="employee-id" placeholder="Employee ID (e.g. 1001)" required>
      <button type="submit">Search</button>
    </form>
    <p id="error" style="display:none"></p>
    <dl id="result" style="display:none">
      <dt>Employee ID</dt><dd id="r-id"></dd>
      <dt>Name</dt><dd id="r-name"></dd>
      <dt>Salary</dt><dd id="r-salary"></dd>
      <dt>Date of Join</dt><dd id="r-doj"></dd>
      <dt>Description</dt><dd id="r-desc"></dd>
    </dl>
  </div>

<script>
const CONFIG = {
  domain: "__COGNITO_DOMAIN__",
  clientId: "__COGNITO_CLIENT_ID__",
  redirectUri: "__REDIRECT_URI__",
  scope: "openid email profile",
};

function base64UrlEncode(buffer) {
  let str = "";
  for (const b of new Uint8Array(buffer)) str += String.fromCharCode(b);
  return btoa(str).replace(/\\+/g, "-").replace(/\\//g, "_").replace(/=+$/, "");
}

function randomVerifier() {
  const bytes = new Uint8Array(64);
  crypto.getRandomValues(bytes);
  return base64UrlEncode(bytes.buffer);
}

async function challengeFromVerifier(verifier) {
  const data = new TextEncoder().encode(verifier);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return base64UrlEncode(digest);
}

// Kicks off the Authorization Code + PKCE flow: store a fresh code_verifier
// for this browser session, then redirect to Cognito Managed Login with its
// derived code_challenge — Cognito redirects back here with ?code=... once
// the user authenticates.
async function login() {
  const verifier = randomVerifier();
  sessionStorage.setItem("pkce_verifier", verifier);
  const challenge = await challengeFromVerifier(verifier);
  const params = new URLSearchParams({
    client_id: CONFIG.clientId,
    response_type: "code",
    scope: CONFIG.scope,
    redirect_uri: CONFIG.redirectUri,
    code_challenge: challenge,
    code_challenge_method: "S256",
  });
  window.location.href = `https://${CONFIG.domain}/oauth2/authorize?${params.toString()}`;
}

// Exchanges the authorization code for tokens, proving this request came
// from the same client that started the flow via the stored code_verifier
// instead of a client secret (this is a public client with none).
async function exchangeCodeForTokens(code) {
  const verifier = sessionStorage.getItem("pkce_verifier");
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: CONFIG.clientId,
    code,
    redirect_uri: CONFIG.redirectUri,
    code_verifier: verifier,
  });
  const resp = await fetch(`https://${CONFIG.domain}/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });
  if (!resp.ok) throw new Error("Token exchange failed");
  const tokens = await resp.json();
  // The API requires the ID token specifically, not the access token.
  sessionStorage.setItem("id_token", tokens.id_token);
}

function logout() {
  sessionStorage.removeItem("id_token");
  sessionStorage.removeItem("pkce_verifier");
  showLoginView();
}

function showLoginView() {
  document.getElementById("login-view").style.display = "block";
  document.getElementById("app-view").style.display = "none";
  document.getElementById("logout-btn").style.display = "none";
}

function showAppView() {
  document.getElementById("login-view").style.display = "none";
  document.getElementById("app-view").style.display = "block";
  document.getElementById("logout-btn").style.display = "inline-block";
}

async function searchEmployee(id) {
  const idToken = sessionStorage.getItem("id_token");
  const errorEl = document.getElementById("error");
  const resultEl = document.getElementById("result");
  errorEl.style.display = "none";
  resultEl.style.display = "none";

  // Relative path: resolves against the current page (".../<stage>/"), so
  // it lands on the same API Gateway stage's /employee/{id} route.
  const resp = await fetch(`employee/${encodeURIComponent(id)}`, {
    headers: { Authorization: `Bearer ${idToken}` },
  });

  if (resp.status === 404) {
    errorEl.textContent = "No employee found for that ID.";
    errorEl.style.display = "block";
    return;
  }
  if (!resp.ok) {
    errorEl.textContent = `Lookup failed (HTTP ${resp.status}).`;
    errorEl.style.display = "block";
    return;
  }

  const data = await resp.json();
  document.getElementById("r-id").textContent = data.employeeId;
  document.getElementById("r-name").textContent = data.name;
  document.getElementById("r-salary").textContent = data.salary;
  document.getElementById("r-doj").textContent = data.dateOfJoin;
  document.getElementById("r-desc").textContent = data.description;
  resultEl.style.display = "block";
}

document.getElementById("login-btn").addEventListener("click", login);
document.getElementById("logout-btn").addEventListener("click", logout);
document.getElementById("search-form").addEventListener("submit", (e) => {
  e.preventDefault();
  searchEmployee(document.getElementById("employee-id").value.trim());
});

(async function init() {
  const url = new URL(window.location.href);
  const code = url.searchParams.get("code");
  if (code) {
    try {
      await exchangeCodeForTokens(code);
    } catch (e) {
      console.error(e);
    }
    window.history.replaceState({}, document.title, CONFIG.redirectUri);
  }
  if (sessionStorage.getItem("id_token")) {
    showAppView();
  } else {
    showLoginView();
  }
})();
</script>
</body>
</html>
"""


def handler(event, context):
    body = (
        PAGE_TEMPLATE.replace("__COGNITO_DOMAIN__", COGNITO_DOMAIN)
        .replace("__COGNITO_CLIENT_ID__", COGNITO_CLIENT_ID)
        .replace("__REDIRECT_URI__", REDIRECT_URI)
    )
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "text/html"},
        "body": body,
    }
