#!/bin/sh -l

set -ex

if [ -n "$INPUT_PATH" ]; then
  # Allow user to change directories in which to run Fly commands.
  cd "$INPUT_PATH" || exit
fi

PR_NUMBER=$(jq -r .number /github/workflow/event.json)
if [ -z "$PR_NUMBER" ]; then
  echo "This action only supports pull_request actions."
  exit 1
fi

REPO_OWNER=$(jq -r .event.base.repo.owner /github/workflow/event.json)
REPO_NAME=$(jq -r .event.base.repo.name /github/workflow/event.json)
EVENT_TYPE=$(jq -r .action /github/workflow/event.json)

# Default the Fly app name to pr-{number}-{repo_owner}-{repo_name}
app="${INPUT_NAME:-pr-$PR_NUMBER-open-decision}"
region="${INPUT_REGION:-${FLY_REGION:-iad}}"
org="${INPUT_ORG:-${FLY_ORG:-personal}}"
image="$INPUT_IMAGE"
config="$INPUT_CONFIG"

sed -i'.original' s/od-api/"$app"/g apps/api/fly.toml

if ! echo "$app" | grep "$PR_NUMBER"; then
  echo "For safety, this action requires the app's name to contain the PR number."
  exit 1
fi

# PR was closed - remove the Fly app if one exists and exit.
if [ "$EVENT_TYPE" = "closed" ]; then
  flyctl apps destroy "$app" -y || true
  exit 0
fi

if ! flyctl status --app "$app"; then
  flyctl apps create --name "$app"
  flyctl secrets set DATABASE_URL="$DATABASE_URL" ACCESS_TOKEN_SECRET="$ACCESS_TOKEN_SECRET" ADMIN_ACCOUNT_WHITELIST="$ADMIN_ACCOUNT_WHITELIST" DEV_ACCOUNT_WHITELIST="$DEV_ACCOUNT_WHITELIST" EMAIL_FROM_ADDRESS="$EMAIL_FROM_ADDRESS" FEATURE_WHITELIST="$FEATURE_WHITELIST" PUBLIC_API_DOCUMENTATION="$PUBLIC_API_DOCUMENTATION" REFRESH_TOKEN_SECRET="$REFRESH_TOKEN_SECRET" SMTP_HOST="$SMTP_HOST" SMTP_PASSWORD="$SMTP_PASSWORD" SMTP_PORT="$SMTP_PORT" SMTP_USERNAME="$SMTP_USERNAME" --config "$config" --app "$app"
elif [ "$INPUT_UPDATE" != "false" ]; then
  flyctl deploy --config "$config" --app "$app" --region "$region" --image "$image" --region "$region" --strategy immediate
fi

# Attach postgres cluster to the app if specified.
if [ -n "$INPUT_POSTGRES" ]; then
  flyctl postgres attach --postgres-app "$INPUT_POSTGRES" || true
fi

# Make some info available to the GitHub workflow.
fly status --app "$app" --json >status.json
hostname=$(jq -r .Hostname status.json)
appid=$(jq -r .ID status.json)
echo "::set-output name=hostname::$hostname"
echo "::set-output name=url::https://$hostname"
echo "::set-output name=id::$appid"
