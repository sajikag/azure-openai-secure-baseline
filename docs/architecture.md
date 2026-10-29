# Architecture

```mermaid
flowchart LR
    subgraph VNet["Virtual network (10.20.0.0/16)"]
        subgraph WL["snet-workload"]
            App["Workload<br/>(App Service / VM / container)<br/>runs as user-assigned<br/>managed identity"]
        end
        subgraph PE["snet-private-endpoints<br/>NSG: allow 443 from workload only"]
            PEA["Private endpoint<br/>Azure OpenAI"]
            PEK["Private endpoint<br/>Key Vault"]
        end
    end

    DNS["Private DNS zones<br/>privatelink.openai.azure.com<br/>privatelink.vaultcore.azure.net"]
    AOAI["Azure OpenAI<br/>public access: off<br/>API keys: off<br/>outbound: restricted<br/>model + version pinned"]
    KV["Key Vault<br/>RBAC only · private only<br/>purge protection"]
    LAW["Log Analytics<br/>(+ optional Sentinel)"]
    Entra["Microsoft Entra ID"]
    Budget["Budget alerts<br/>50% · 80% · 100% forecast"]

    App -- "HTTPS + bearer token" --> PEA --> AOAI
    App -- "HTTPS + bearer token" --> PEK --> KV
    App -. "token request" .-> Entra
    App -. "name resolution" .-> DNS
    AOAI -- "audit & request logs" --> LAW
    KV -- "audit logs" --> LAW
    Budget -. "watches" .-> AOAI

    Internet(("Internet")) -- "blocked" --x AOAI
```

## Request flow

1. The workload asks Entra ID for a token for `https://cognitiveservices.azure.com` using its managed identity. No secret is involved.
2. It resolves `<account>.openai.azure.com`. The linked private DNS zone returns the private endpoint's IP.
3. The call travels over HTTPS to the private endpoint. The NSG admits it because it comes from the workload subnet.
4. Azure OpenAI validates the token and checks the caller holds *Cognitive Services OpenAI User* on the account.
5. The request and its outcome are logged to Log Analytics.

Any call from outside the VNet, or with an API key, fails at step 3 or 4.

## Module map

| Module | Creates |
|---|---|
| `monitoring.bicep` | Log Analytics workspace, optional Sentinel onboarding |
| `network.bicep` | VNet, two subnets, two NSGs |
| `identity.bicep` | User-assigned managed identity for the workload |
| `private-dns.bicep` | Private DNS zone + VNet link (used twice) |
| `openai.bicep` | Azure OpenAI account, model deployment, role assignment, diagnostics |
| `keyvault.bicep` | Key Vault, role assignment, diagnostics |
| `private-endpoint.bicep` | Private endpoint + DNS registration (used twice) |
| `budget.bicep` | Monthly budget with three alerts |
