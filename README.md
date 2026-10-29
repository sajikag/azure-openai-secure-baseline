# azure-openai-secure-baseline

[![validate](https://github.com/sajikag/azure-openai-secure-baseline/actions/workflows/validate.yml/badge.svg)](https://github.com/sajikag/azure-openai-secure-baseline/actions/workflows/validate.yml)

A threat-modelled Bicep reference for running **Azure OpenAI with no public endpoint, no API keys and no unmonitored access**.

Most "deploy Azure OpenAI" samples give you a public endpoint and a key. That is fine for a demo and a liability in production: a key pasted into one log file is standing access to your model and your bill. This repo is the opposite starting point. Every control maps to a specific threat in [`docs/threat-model.md`](docs/threat-model.md), and the gaps it leaves are listed just as explicitly.

## What it deploys

| Control | How |
|---|---|
| **No internet exposure** | Public network access disabled; reachable only through a private endpoint |
| **No API keys** | Local auth disabled. The workload authenticates with a managed identity, so there is nothing to leak |
| **Network segmentation** | NSG lets only the workload subnet reach the private endpoints on 443; all other inbound is denied |
| **Exfiltration control** | The service's outbound network access is restricted to an empty allow-list |
| **Least privilege** | Workload gets inference-only and secret-read-only roles, nothing else |
| **Hardened secrets store** | Key Vault: RBAC-only, private-only, soft delete + purge protection |
| **Audit trail** | All Azure OpenAI and Key Vault logs to Log Analytics; optional Microsoft Sentinel |
| **Cost and abuse guardrails** | Tokens-per-minute cap on the deployment; budget alerts at 50 %, 80 % and 100 % forecast |
| **No silent changes** | Model version pinned with auto-upgrade off; content-filter policy pinned |
| **Policy as code** | CI lints every change, with secret-handling linter rules set to fail the build |

See [`docs/architecture.md`](docs/architecture.md) for the diagram and request flow.

## Repository layout

```
infra/
  main.bicep            orchestration and parameters
  main.bicepparam       example parameter values
  modules/              network, identity, private-dns, private-endpoint,
                        openai, keyvault, monitoring, budget
docs/
  threat-model.md       assets, adversaries, threats → mitigations, residual risks
  architecture.md       diagram, request flow, module map
scripts/
  deploy.ps1            what-if preview or deploy
  teardown.ps1          confirmed resource-group deletion
.github/workflows/
  validate.yml          lint + compile on every push and PR
bicepconfig.json        linter rules
```

## Deploy

**Prerequisites:** an Azure subscription with access to Azure OpenAI, Azure CLI 2.53+, PowerShell 7+, and Owner (or Contributor + User Access Administrator) on the subscription, since the template creates role assignments.

1. Edit `infra/main.bicepparam`: set `prefix`, `location` and `budgetContactEmails`. Check the region offers your model and deployment type.
2. Preview, then deploy:

   ```powershell
   az login
   ./scripts/deploy.ps1 -ResourceGroup rg-aoai-baseline -WhatIf
   ./scripts/deploy.ps1 -ResourceGroup rg-aoai-baseline
   ```

3. Tear down when finished:

   ```powershell
   ./scripts/teardown.ps1 -ResourceGroup rg-aoai-baseline
   ```

## Calling the model

The endpoint is private, so calls must come from something in `snet-workload` (App Service with VNet integration, a VM, a Container App) running as the deployed managed identity. No key is involved:

```python
from azure.identity import ManagedIdentityCredential, get_bearer_token_provider
from openai import AzureOpenAI

credential = ManagedIdentityCredential(client_id="<workloadIdentityClientId output>")
token_provider = get_bearer_token_provider(credential, "https://cognitiveservices.azure.com/.default")

client = AzureOpenAI(
    azure_endpoint="<openAiEndpoint output>",
    azure_ad_token_provider=token_provider,
    api_version="2024-10-21",
)
reply = client.chat.completions.create(
    model="<modelDeploymentName output>",
    messages=[{"role": "user", "content": "Hello"}],
)
print(reply.choices[0].message.content)
```

Run the same code from your laptop and it fails, which is the point.

## Design decisions

- **Managed identity over keys.** A key is a bearer secret that works from anywhere. A managed identity token is short-lived, issued only to a specific Azure resource, and cannot be exported. Disabling local auth removes the key path entirely rather than just not using it.
- **User-assigned over system-assigned identity.** Role assignments exist before the workload is deployed, and the identity survives the workload being rebuilt.
- **Explicit deny on the private-endpoint subnet.** The default NSG rules allow all VNet-internal traffic. Overriding that means a compromised resource elsewhere in the VNet still can't reach the model.
- **Throughput cap as a security control.** Capacity is usually treated as a performance setting. Here it also bounds how much damage a compromised workload can do per minute.
- **Bicep over Terraform.** For an Azure-only footprint, Bicep gets new resource properties (such as outbound restriction) on day one, needs no state file to protect, and compiles to native ARM.
- **`GlobalStandard` by default.** It has the widest model availability. Switch to `DataZoneStandard` or `Standard` if data must stay in a geography.

## Known limitations

Spelled out in full in the [threat model](docs/threat-model.md#residual-risks-and-known-gaps). The main ones: prompt and completion content isn't logged (that needs a gateway); the workload is trusted, so prompt-injection-driven misuse is bounded but not prevented; budgets alert rather than stop spend; and no Sentinel detection rules are included yet.

## Roadmap

- [ ] API Management gateway with per-caller quotas and redacted request logging
- [ ] Sentinel analytics rules for anomalous token usage and access from unexpected identities
- [ ] Budget action group that automatically revokes inference access
- [ ] Azure Monitor Private Link Scope for private log ingestion
- [ ] PSRule for Azure checks in CI

## Disclaimer

A reference implementation written from scratch for learning and discussion. Review it against your own requirements before production use. Not affiliated with, and contains no code from, any employer or client.

## License

[MIT](LICENSE)
