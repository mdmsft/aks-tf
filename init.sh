#!/usr/bin/env sh

set -e -o pipefail

tenant_id=
subscription_id=
client_id=
client_secret=
resource_group_name=
storage_account_name=

terraform init \
    -backend-config="tenant_id=$tenant_id" \
    -backend-config="subscription_id=$subscription_id" \
    -backend-config="client_id=$client_id" \
    -backend-config="client_secret=$client_secret" \
    -backend-config="resource_group_name=$resource_group_name" \
    -backend-config="storage_account_name=$storage_account_name"