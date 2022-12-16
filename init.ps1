$tenant_id = $env:TF_STATE_tenant_id
$subscription_id = $env:TF_STATE_subscription_id
$client_id = $env:TF_STATE_client_id
$client_secret = $env:TF_STATE_client_secret
$resource_group_name = $env:TF_STATE_resource_group_name
$storage_account_name = $env:TF_STATE_storage_account_name
$key = (Get-Item -Path .).BaseName

terraform init `
    -backend-config="tenant_id=$tenant_id" `
    -backend-config="subscription_id=$subscription_id" `
    -backend-config="client_id=$client_id" `
    -backend-config="client_secret=$client_secret" `
    -backend-config="resource_group_name=$resource_group_name" `
    -backend-config="storage_account_name=$storage_account_name" `
    -backend-config="key=$key" `
    -upgrade -reconfigure