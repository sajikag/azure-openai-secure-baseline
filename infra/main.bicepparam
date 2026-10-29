using './main.bicep'

// Example values. Copy this file, adjust, and keep real email addresses out of git if you prefer.
param prefix = 'aoaisec'
param location = 'swedencentral'
param deploymentSku = 'GlobalStandard'
param deploymentCapacity = 10
param monthlyBudgetAmount = 50
param budgetContactEmails = [
  'alerts@example.com'
]
param enableSentinel = false
