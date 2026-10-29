# Threat model

## Scope

A single application ("the workload") calls one Azure OpenAI model deployment. The template protects the **infrastructure path** between that workload and the model: identity, network, logging and spend. It does not try to make the model itself safe; it narrows who can reach the model, what the model's host can reach, and how quickly misuse is noticed.

## Assets

| Asset | Why it matters |
|---|---|
| Model access (inference endpoint) | Anyone who can call it can spend money and generate content in your name |
| Prompts and completions in transit | May contain customer or proprietary data |
| Workload secrets in Key Vault | Third-party credentials; compromise extends beyond Azure |
| Audit logs | The only record of who used the model and when |
| Budget | Runaway usage is a real financial and availability risk |

## Adversaries considered

1. **External attacker** with no network path and no credentials.
2. **Attacker holding a leaked credential**: an API key pasted into a repo, chat or log.
3. **Compromised or misbehaving workload**, including one manipulated by prompt injection into abusing its own access.
4. **Over-privileged insider** or automation account.

## Threats and mitigations

| # | Threat | Mitigation in this template | Where |
|---|---|---|---|
| T1 | Endpoint reachable from the internet | `publicNetworkAccess: Disabled`, network ACL default-deny, private endpoint only | `openai.bicep`, `private-endpoint.bicep` |
| T2 | Leaked API key gives standing access | `disableLocalAuth: true`: keys do not work at all. Access is Entra ID tokens issued to a managed identity, which cannot be copied out | `openai.bicep`, `identity.bicep` |
| T3 | Lateral movement inside the VNet to the endpoint | NSG on the private-endpoint subnet allows HTTPS from the workload subnet only and denies all other inbound, including other VNet traffic | `network.bicep` |
| T4 | Data exfiltration via the service calling out (e.g. "on your data" connectors pointed at attacker URLs) | `restrictOutboundNetworkAccess: true` with an empty allow-list | `openai.bicep` |
| T5 | Workload identity over-privileged | Data-plane roles only: *Cognitive Services OpenAI User* (inference, no management, no key listing) and *Key Vault Secrets User* (read, no write or delete) | `openai.bicep`, `keyvault.bicep` |
| T6 | Secret tampering or destruction | Key Vault RBAC-only, private-only, soft delete 90 days, purge protection | `keyvault.bicep` |
| T7 | Misuse goes unnoticed | All log categories from Azure OpenAI and Key Vault streamed to Log Analytics; optional Sentinel onboarding for detection rules | `monitoring.bicep` |
| T8 | Cost exhaustion / denial of wallet | Deployment capacity caps tokens per minute; budget alerts at 50 % and 80 % actual and 100 % forecast | `openai.bicep`, `budget.bicep` |
| T9 | Silent behaviour change from a model upgrade | Model version pinned, `versionUpgradeOption: NoAutoUpgrade` | `openai.bicep` |
| T10 | Harmful output categories | Default content-filter policy pinned explicitly so it can't drift | `openai.bicep` |
| T11 | Configuration drift / insecure change merged | Everything is code; CI lints and compiles every pull request with secret-handling rules set to *error* | `bicepconfig.json`, `.github/workflows/validate.yml` |

## Residual risks and known gaps

These are deliberate scope limits, and the most interesting places to extend the work:

- **Prompt and completion content is not logged.** Azure OpenAI diagnostic logs record who called what and when, not what was said. Content-level auditing needs a gateway (e.g. Azure API Management with request logging), which brings its own data-retention risk.
- **The workload itself is trusted.** If it is compromised or prompt-injected, it can still make any inference call its identity allows, within the throughput cap. Per-user quotas, output monitoring and anomaly detection would sit in front of the model.
- **Budgets alert; they do not stop spend.** A hard stop needs an action group that disables the deployment or removes the role assignment.
- **No Sentinel analytics rules are shipped.** Onboarding is optional and rule content is left to the operator.
- **Single region, no customer-managed key.** Microsoft-managed encryption at rest; no failover.
- **Log Analytics is reachable over public endpoints** (authenticated). An Azure Monitor Private Link Scope would close this.
- **Supply chain of the model is out of scope.** This template cannot verify model weights or provider-side controls.
