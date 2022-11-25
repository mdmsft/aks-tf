#!/usr/bin/env sh

set -e -o pipefail

resource_group_name=$BACKEND_RESOURCE_GROUP_NAME
storage_account_name=$BACKEND_STORAGE_ACCOUNT_NAME

terraform init \
    -backend-config="resource_group_name=$resource_group_name" \
    -backend-config="storage_account_name=$storage_account_name"