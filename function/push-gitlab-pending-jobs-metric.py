#!/bin/python
import logging
import requests
import time
import boto3
import backoff
import os
import ipaddress
from datetime import datetime, timedelta
from botocore.exceptions import ClientError

MAX_RETRIES = 8
ACTIVITY_SINCE = os.getenv('ACTIVITY_SINCE')
ALLOWED_IP_RANGE = os.getenv('ALLOWED_IP_RANGE', [])
TOKEN_SSM_PATH = os.getenv('TOKEN_SSM_PATH')
GITLAB_URI = os.getenv('GITLAB_URI')
ASG_NAME = os.getenv('ASG_NAME')
REGION = os.getenv('AWS_REGION')
RUNNER_JOB_TAGS = [tag.strip() for tag in os.getenv('RUNNER_JOB_TAGS', default="").split(',')]
HAS_RUNNER_TAGS = any(tag.strip() for tag in RUNNER_JOB_TAGS)
RUNNERS_PER_INSTANCE = int(os.getenv('RUNNERS_PER_INSTANCE'))
METRIC_NAMESPACE = os.getenv('METRIC_NAMESPACE')
NARROW_TO_MEMBERSHIP_RAW = os.getenv('NARROW_TO_MEMBERSHIP')
NARROW_TO_MEMBERSHIP = True if NARROW_TO_MEMBERSHIP_RAW.lower() == 'true' else False
LOG_LEVEL_RAW = os.getenv('LOG_LEVEL')
LOG_LEVEL = logging.INFO
if LOG_LEVEL_RAW.lower() == 'debug':
    LOG_LEVEL = logging.DEBUG

LOGGER = logging.getLogger('myLogger')
LOGGER.setLevel(LOG_LEVEL)


def no_request_limit_exceeded_code(e):
    return e.response.get('Error', {}).get('Code', 'Unknown') != 'RequestLimitExceeded'


@backoff.on_exception(backoff.expo,
                      ClientError,
                      max_tries=MAX_RETRIES,
                      giveup=no_request_limit_exceeded_code)
def get_parameter(ssm_client, **kwargs):
    return ssm_client.get_parameter(**kwargs)


@backoff.on_exception(backoff.expo,
                      ClientError,
                      max_tries=MAX_RETRIES,
                      giveup=no_request_limit_exceeded_code)
def put_metric_data(cw_client, **kwargs):
    return cw_client.put_metric_data(**kwargs)


@backoff.on_exception(backoff.expo,
                      ClientError,
                      max_tries=MAX_RETRIES,
                      giveup=no_request_limit_exceeded_code)
def describe_auto_scaling_groups(asg_client, **kwargs):
    return asg_client.describe_auto_scaling_groups(**kwargs)


@backoff.on_exception(backoff.expo,
                      requests.exceptions.Timeout,
                      max_tries=MAX_RETRIES)
def get_request(*args, **kwargs):
    return requests.get(*args, **kwargs)


def check_ip(SOURCE_IP_ADDRESS, ALLOWED_IP_RANGE):
    for cidr in ALLOWED_IP_RANGE:
        try:
            ipaddress.ip_network(cidr.strip(), False)
        except ValueError:
            LOGGER.error('Invalid input CIDR range: %s.' % (cidr))
            return False

    cidr_networks = [ipaddress.ip_network(cidr, False) for cidr in ALLOWED_IP_RANGE]
    ip_address = ipaddress.ip_address(SOURCE_IP_ADDRESS)
    for network in cidr_networks:
        if ip_address in network:
            return True
    LOGGER.error('%s was blocked as not in valid CIDR  allow range: %s.' % (SOURCE_IP_ADDRESS, ALLOWED_IP_RANGE))
    return False


def get_all_project_ids(token):
    project_ids = []
    link = '{}/api/v4/projects?pagination=keyset&per_page=50&order_by=id&sort=asc&simple=true{}'.format(GITLAB_URI, '&membership=true' if NARROW_TO_MEMBERSHIP else '')
    now = datetime.utcnow()
    hours_ago = now - timedelta(hours=int(ACTIVITY_SINCE))
    hours_ago_timestamp_str = '{}Z'.format(hours_ago.isoformat(timespec='seconds'))
    LOGGER.info("Searching for projects with last activity after {}".format(hours_ago_timestamp_str))
    total_numb_of_projects = 0
    while True:
        res = get_request(link, headers={'PRIVATE-TOKEN': token})
        if res.status_code != 200:
            raise Exception('Error retrieving all the projects')
        total_numb_of_projects += len(res.json())
        for project in res.json():
            pid = project['id']
            last_activity_str = project['last_activity_at']
            last_activity = datetime.strptime(last_activity_str, '%Y-%m-%dT%H:%M:%S.%fZ')
            if last_activity > hours_ago:
                LOGGER.debug('Found project with last activity {}'.format(last_activity_str))
                project_ids.extend([pid])
        if 'Link' not in res.headers:
            break
        link = res.headers['Link'].split('<')[1].split('>')[0]
    LOGGER.info("Found project ids: {}".format(project_ids))
    LOGGER.info("Number of projects processes: {}".format(total_numb_of_projects))
    return project_ids


def get_pending_jobs(project_id, token):
    res = get_request('{uri}/api/v4/projects/{pid}/jobs?scope[]=pending'.format(uri=GITLAB_URI, pid=project_id),
                      headers={'PRIVATE-TOKEN': token})
    if res.status_code != 200:
        LOGGER.error('Error retrieving the jobs of the project id %s. Return code: %s' % (project_id, res.status_code))
        return []
        # raise Exception('Error retrieving the jobs of the project id %s' % project_id)
    job_tag_list = []
    for job in res.json():
        # Ensure the runner tags contains all of the job tags
        if all(item in RUNNER_JOB_TAGS for item in list(filter(None, job['tag_list']))):
            job_tag_list.append(job)
    return job_tag_list


def get_running_jobs(project_id, token):
    res = get_request('{uri}/api/v4/projects/{pid}/jobs?scope[]=running'.format(uri=GITLAB_URI, pid=project_id),
                      headers={'PRIVATE-TOKEN': token})
    if res.status_code != 200:
        LOGGER.error('Error retrieving the jobs of the project id %s. Return code: %s' % (project_id, res.status_code))
        return []
        # raise Exception('Error retrieving the jobs of the project id %s' % project_id)
    # If the job requires runner tags, heck the lambda tags have them all
    job_tag_list = []
    for job in res.json():
        # Ensure the runner tags contains all of the job tags
        if all(item in RUNNER_JOB_TAGS for item in list(filter(None, job['tag_list']))):
            job_tag_list.append(job)
    return job_tag_list


def get_all_pending_and_running_job_ids(token):
    pending_job_ids = []
    running_job_ids = []
    project_ids = get_all_project_ids(token)
    for project_id in project_ids:
        pending_jobs = get_pending_jobs(project_id, token)
        running_jobs = get_running_jobs(project_id, token)
        tag_log = " with {} {}".format("tags" if len(RUNNER_JOB_TAGS) > 1 else "tag", ' or '.join(f'"{item}"' for item in RUNNER_JOB_TAGS)) if HAS_RUNNER_TAGS else ""
        if len(pending_jobs):
            LOGGER.info("Number of pending jobs for project id {}: {}{}".format(project_id, len(pending_jobs),  tag_log))
            pending_job_ids.extend(pending_job['id'] for pending_job in pending_jobs)
        if len(running_jobs):
            LOGGER.info("Number of running jobs for project id {}: {}".format(project_id, len(running_jobs),  tag_log))
            running_job_ids.extend(running_job['id'] for running_job in running_jobs)
    return pending_job_ids, running_job_ids


def get_number_of_pending_and_running_jobs(token):
    pending_job_ids, running_job_ids = get_all_pending_and_running_job_ids(token)
    return len(pending_job_ids), len(running_job_ids)


def get_asg_healthy_instances_in_service(asg_client):
    instances_in_service = 0
    LOGGER.info("Listing instances in autoscaling group {}".format(ASG_NAME))
    result = describe_auto_scaling_groups(asg_client, AutoScalingGroupNames=[ASG_NAME])
    instances = result['AutoScalingGroups'][0].get('Instances', [])
    LOGGER.info("Number of instances: {}".format(len(instances)))
    for instance in instances:
        LOGGER.info("[{}] HealthStatus: {} - LifecycleState: {}".format(instance['InstanceId'],
                                                                        instance['HealthStatus'],
                                                                        instance['LifecycleState']))
        if instance['HealthStatus'] == 'Healthy' and instance['LifecycleState'] == 'InService':
            instances_in_service += 1
    return instances_in_service


def handler(event, context):
    # Check if request originated from http (url), if it did and we have IPs to check verify the source is allowed
    if 'requestContext' in event and 'http' in event['requestContext'] and 'sourceIp' in event['requestContext']['http'] and ALLOWED_IP_RANGE:
        if not check_ip(event["requestContext"]["http"]["sourceIp"], ALLOWED_IP_RANGE.split(',')):
            return {
                "statusCode": 403,
                "body": '',
            }

    ssm_client = boto3.client('ssm', region_name=REGION)
    result = get_parameter(ssm_client, Name=TOKEN_SSM_PATH, WithDecryption=True)
    token = result['Parameter']['Value']

    pending_jobs, running_jobs = get_number_of_pending_and_running_jobs(token)
    tag_log = " with {} {}".format("tags" if len(RUNNER_JOB_TAGS) > 1 else "tag", ' or '.join(f'"{item}"' for item in RUNNER_JOB_TAGS)) if HAS_RUNNER_TAGS else ""
    LOGGER.info("Total number of pending jobs: {}{}".format(pending_jobs, tag_log))
    LOGGER.info("Total number of running jobs: {}{}".format(running_jobs, tag_log))

    asg_client = boto3.client('autoscaling', region_name=REGION)
    healthy_instances_in_service = get_asg_healthy_instances_in_service(asg_client)
    LOGGER.info("Number of HEALTHY instances: {}".format(healthy_instances_in_service))

    runners_overall_load = 100
    if healthy_instances_in_service:
        runners_overall_load = float(100 * (pending_jobs + running_jobs)) / float(healthy_instances_in_service * RUNNERS_PER_INSTANCE)
    LOGGER.info("Runners overall load: {}".format(runners_overall_load))

    cw_client = boto3.client('cloudwatch', region_name=REGION)
    timestamp = time.time()

    put_metric_data(
        cw_client,
        Namespace=METRIC_NAMESPACE,
        MetricData=[
            {
                'MetricName': 'NumberOfPendingJobs',
                'Dimensions': [
                    {
                        'Name': 'Job Status',
                        'Value': 'Pending'
                    }
                ],
                'Timestamp': timestamp,
                'Value': pending_jobs,
                'Unit': 'Count',
                'StorageResolution': 60
            },
            {
                'MetricName': 'NumberOfRunningJobs',
                'Dimensions': [
                    {
                        'Name': 'Job Status',
                        'Value': 'Running'
                    }
                ],
                'Timestamp': timestamp,
                'Value': running_jobs,
                'Unit': 'Count',
                'StorageResolution': 60
            },
            {
                'MetricName': 'RunnersOverallLoad',
                'Dimensions': [
                    {
                        'Name': 'Runners Overall Load',
                        'Value': 'OverallLoadPercentage'
                    }
                ],
                'Timestamp': timestamp,
                'Value': runners_overall_load,
                'Unit': 'Percent',
                'StorageResolution': 60
            },
        ]
    )
