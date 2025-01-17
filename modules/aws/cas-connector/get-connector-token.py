#!/usr/bin/env python3

# © Copyright 2022 HP Development Company, L.P.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import argparse
import datetime
import json
import requests
import subprocess

METADATA_URL = "http://169.254.169.254/latest/meta-data/"


def create_connector_name():
    """A function to create a custom connector name
    
    Uses metadata server to access instance data, which is used to create the connector name.
    
    Returns:
        string: a string for the connector name
    """

    zone     = requests.get(METADATA_URL + "placement/availability-zone").text
    name     = get_instance_name(zone[:-1])
    iso_time = datetime.datetime.utcnow().isoformat(timespec='seconds').replace(':','').replace('-','') + 'Z'

    connector_name = f"{zone}-{name}-{iso_time}"

    return connector_name


def get_instance_name(region):
    """A function to get the current EC2 instance name
    
    Uses AWS CLI 'describe-tags' to retrieve the current EC2 instance name.
    
    Args:
        region (str): the AWS region to perform 'describe-tags' using AWS CLI
    Returns:
        string: a string for the EC2 instance name
    """

    instance_id   = requests.get(METADATA_URL + "instance-id").text
    filter_string = f"Name=resource-id,Values={instance_id}"

    cmd = f'aws ec2 describe-tags --region {region} --filters {filter_string}'

    instance_tags = subprocess.run(cmd.split(' '),  stdout=subprocess.PIPE).stdout.decode('utf-8')
    instance_tags = json.loads(instance_tags)

    instance_name = instance_tags.get('Tags')[0].get('Value')

    return instance_name


def load_service_account_key(path):
    print(f"Loading CAS Manager deployment service account key from {path}...")

    with open(path) as f:
        dsa_key = json.load(f)

    return dsa_key


def cas_mgr_login(key):
    print(f"Signing in to CAS Manager with key {key['keyName']}...")

    payload = {
        'username': key['username'], 
        'password': key['apiKey'],
    }
    resp = session.post(
        f"{cas_mgr_api_url}/auth/signin",
        json=payload, 
    )
    resp.raise_for_status()

    token = resp.json()['data']['token']
    session.headers.update({"Authorization": token})


def get_connector_token(key, connector_name):
    print(f"Creating a connector token in deployment {key['deploymentId']}...")

    payload = {
        'deploymentId': key['deploymentId'], 
        'connectorName': connector_name,
    }
    resp = session.post(
        f"{cas_mgr_api_url}/auth/tokens/connector",
        json=payload, 
    )
    resp.raise_for_status()

    return resp.json()['data']['token']


def token_write(token, path):
    print(f"Writing connector token to {path}...")
    with open(path, 'w') as f:
        f.write(token)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="This script uses CAS Manager Deployment Service Account JSON file to create a new connector token.")

    parser.add_argument("cas_mgr", help="specify the path to CAS Manager Deployment Service Account JSON file")
    parser.add_argument("--out", required=True, help="File to write the connector token")
    parser.add_argument("--url", default="https://cas.teradici.com", help="specify the api url")
    parser.add_argument("--insecure", action="store_true", help="Allow unverified HTTPS connection to CAS Manager")

    args = parser.parse_args()

    cas_mgr_api_url = f"{args.url}/api/v1"

    # Set up session to be used for all subsequent calls to CAS Manager
    session = requests.Session()
    if args.insecure:
        session.verify = False

    dsa_key = load_service_account_key(args.cas_mgr)
    cas_mgr_login(dsa_key)
    connector_name = create_connector_name()
    connector_token = get_connector_token(dsa_key, connector_name)
    token_write(connector_token, args.out)
