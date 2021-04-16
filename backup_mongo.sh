#!/bin/bash

set -e

# define the following in your env
# MONGO_URI => mongo host URI
# MONGO_CONNECTIONSTRING => mongo connection string
# MONGO_USERNAME => username for mongodb
# MONGO_PASSWORD => password to authenticate against mongodb
# MONGO_AUTH_DB => name of mongo authentication database
# AZURE_SA => Azure Storage account name
# AZURE_BLOB_CONTAINER => name of the azure storage blob container
# AZURE_SHARE_NAME => name of the azure file share
# AZURE_DESTINATION_KEY => azure storage account destination key
# DB => mongo db to backup

# check the mongo uri
if [ -z "$MONGO_URI" ] && [ -z "$MONGO_CONNECTIONSTRING" ]; then
  echo "Error: you must set the MONGO_URI or MONGO_CONNECTIONSTRING environment variable"
  exit 1
fi

# check the azure args
if [ -z "$AZURE_SA" ] || [ -z "$AZURE_DESTINATION_KEY" ]; then
  echo "Error: you must set all Azure storage account variables AZURE_SA and AZURE_DESTINATION_KEY"
  exit 3
fi

# get the azure destination type and name
if [ ! -z "${AZURE_BLOB_CONTAINER}" ]; then
  AZURE_TYPE=blob
  AZURE_CONTAINER_NAME=${AZURE_BLOB_CONTAINER}
elif [ ! -z "${AZURE_SHARE_NAME}" ]; then
  AZURE_TYPE=file
  AZURE_CONTAINER_NAME=${AZURE_SHARE_NAME}
else
  echo "Error: you must set either AZURE_BLOB_CONTAINER or AZURE_SHARE_NAME"
  exit 4
fi

# check the mongo auth params
if [ -z "$MONGO_USERNAME" ] && [ -z "$MONGO_PASSWORD" ] && [ -z "$MONGO_AUTH_DB" ]; then
  NO_AUTH=${NO_AUTH:-true}
elif [ -z "$MONGO_USERNAME" ] || [ -z "$MONGO_PASSWORD" ] || [ -z "$MONGO_AUTH_DB" ]; then
  echo "Error: you must set all the MongoDB authentication environment variables MONGO_USERNAME, MONGO_PASSWORD and MONGO_AUTH_DB"
  exit 5
fi

DIRECTORY=$(date +%Y-%m-%d)


date
echo "Backing up MongoDB database ${DB}"

echo "Dumping MongoDB $DB database to compressed archive"
if [ ! -z "$MONGO_CONNECTIONSTRING" ]; then
  DB="mongodb"
  mongodump ${MONGO_CONNECTIONSTRING} --archive=$HOME/tmp_dump.gz --gzip
elif [ "$NO_AUTH" = true ]; then
  mongodump --host ${MONGO_URI} --db ${DB} --archive=$HOME/tmp_dump.gz --gzip
else
  mongodump --authenticationDatabase ${MONGO_AUTH_DB} -u ${MONGO_USERNAME} -p ${MONGO_PASSWORD} --host ${MONGO_URI} --db ${DB} --archive=$HOME/tmp_dump.gz --gzip
fi

BACKUP_NAME=${DB}-$(date +%Y%m%d_%H%M%S).gz

if [ ! -z "$AZCOPY_SPA_CLIENT_SECRET" ] && [ ! -z "$AZURE_APP_ID" ] && [ ! -z "$AZURE_TENANT_ID" ]; then
  echo "Logging in to Azure"
  azcopy login --service-principal --application-id ${AZURE_APP_ID} --tenant-id ${AZURE_TENANT_ID}
elif [ ! -z "$AZCOPY_SPA_CLIENT_SECRET" ] || [ ! -z "$AZURE_APP_ID" ] || [ ! -z "$AZURE_TENANT_ID" ]; then
  echo "Error: you must set all the Azure authentication environment variables AZCOPY_SPA_CLIENT_SECRET, AZURE_APP_ID and AZURE_TENANT_ID"
  exit 6
fi

echo "Copying compressed archive to Azure Storage: ${AZURE_SA}.${AZURE_TYPE}/${AZURE_CONTAINER_NAME}/${DIRECTORY}/${BACKUP_NAME}"
azcopy --source $HOME/tmp_dump.gz --destination https://${AZURE_SA}.${AZURE_TYPE}.core.windows.net/${AZURE_CONTAINER_NAME}/${DIRECTORY}/${BACKUP_NAME} --dest-key ${AZURE_DESTINATION_KEY}
yes | azcopy --source $HOME/tmp_dump.gz --destination https://${AZURE_SA}.${AZURE_TYPE}.core.windows.net/${AZURE_CONTAINER_NAME}/latest/${DB}-backup.gz --dest-key ${AZURE_DESTINATION_KEY}

echo "Cleaning up compressed archive"
rm $HOME/tmp_dump.gz

echo 'Backup complete!'
