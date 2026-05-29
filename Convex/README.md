For the Backend service, you need to assign two domains:
1. One for the backend domain, ending with port `:3210`.
2. Another for the site (HTTP) domain, ending with port `:3211`.

**Example:** `https://backend.example.com:3210`, `https://site.example.com:3211`

For the Dashboard service, assign the domain without specifying a port number.

**Example:** `https://dashboard.example.com`


To generate an admin key, use the terminal in Coolify to run the following command inside the backend container:
`./generate_admin_key.sh`
