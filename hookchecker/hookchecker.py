#!/bin/python
import logging.handlers
import requests
import time
import boto3
import botocore
import backoff
import subprocess
from botocore.exceptions import ClientError

LOG_FILENAME = '/var/log/hookchecker.log'
LOG_LEVEL = logging.DEBUG

LOGGER = logging.getLogger('myLogger')
LOGGER.setLevel(LOG_LEVEL)
formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
file_handler = logging.handlers.RotatingFileHandler(LOG_FILENAME, maxBytes=1024*1024, backupCount=5)
file_handler.setFormatter(formatter)
LOGGER.addHandler(file_handler)
stream_handler = logging.StreamHandler()
stream_handler.setFormatter(formatter)
LOGGER.addHandler(stream_handler)


MAX_RETRIES = 8
meta_url = 'http://169.254.169.254/latest/meta-data/'
RUNNER_CONFIG_FILE = '/etc/gitlab-runner/config.toml'


def no_request_limit_exceeded_code(e):
    return e.response.get('Error', {}).get('Code', 'Unknown') != 'RequestLimitExceeded'


@backoff.on_exception(backoff.expo,
                      Exception,
                      max_tries=MAX_RETRIES)
def get_instance_id():
    instance_id_meta_url = meta_url + 'instance-id'
    r = requests.get(url=instance_id_meta_url)
    return r.text


@backoff.on_exception(backoff.expo,
                      Exception,
                      max_tries=MAX_RETRIES)
def get_region():
    region_meta_url = meta_url + 'placement/availability-zone'
    r = requests.get(url=region_meta_url)
    return r.text[:-1]


@backoff.on_exception(backoff.expo,
                      ClientError,
                      max_tries=MAX_RETRIES,
                      giveup=no_request_limit_exceeded_code)
def describe_auto_scaling_instances(instance_ids):
    return asg_client.describe_auto_scaling_instances(InstanceIds=instance_ids)


@backoff.on_exception(backoff.expo,
                      ClientError,
                      max_tries=MAX_RETRIES,
                      giveup=no_request_limit_exceeded_code)
def record_lifecycle_action_heartbeat(**kwargs):
    return asg_client.record_lifecycle_action_heartbeat(**kwargs)


def get_runners():
    runner_found = False
    rtoken = None
    rurl = None
    runners = []
    with open(RUNNER_CONFIG_FILE) as config_file:
        config_file_lines = config_file.readlines()
        for line in config_file_lines:
            if line.strip() == "[[runners]]":
                runner_found = True
                rtoken = None
                rurl = None
            elif runner_found:
                if '=' in line:
                    if line.split('=')[0].strip() == "url":
                        rurl = line.split('=')[1].strip().strip('"')
                    elif line.split('=')[0].strip() == "token":
                        rtoken = line.split('=')[1].strip().strip('"')
                    if rurl and rtoken:
                        runners.append({'url': rurl, 'token': rtoken})
                        runner_found = False
    return runners


def deregister_runners():
    LOGGER.info('Start deregistring the runned')
    unregister_command_pattern = 'gitlab-runner unregister --url {url} --token {token}'
    runners = get_runners()
    for runner in runners:
        unregister_command = unregister_command_pattern.format(url=runner['url'], token=runner['token'])
        LOGGER.debug(unregister_command)
        try:
            subprocess.check_output(unregister_command.split())
            LOGGER.info("Runner %s deregistered" % runner['token'])
        except Exception as e:
            LOGGER.error("Error deregistering the runner %s: %s" % (runner['token'], str(e)))


def wait_for_running_job_to_finish(lh_name, asg_name, instance_id):
    LOGGER.info('Waiting for runners to finish the last build'.format())
    running_processes_cmd = 'ps aux'
    running_jobs = True
    while running_jobs:
        running_jobs = False
        time.sleep(5)
        res = subprocess.check_output(running_processes_cmd.split())
        for process in res.split('\n'):
            if "/bin/bash gitlab-runner" in process:
                LOGGER.debug("Found runner still running: \n%s" % process)
                running_jobs = True
                break
        if running_jobs:
            LOGGER.debug("Refreshing the lifecycle hook heartbeat")
            record_lifecycle_action_heartbeat(
                LifecycleHookName=lh_name,
                AutoScalingGroupName=asg_name,
                InstanceId=instance_id
            )
    LOGGER.info("There are no (more) running runners!")


@backoff.on_exception(backoff.expo,
                      botocore.exceptions.ClientError,
                      max_tries=MAX_RETRIES,
                      giveup=no_request_limit_exceeded_code)
def complete_lifecycle_action(*args, **kwargs):
    return asg_client.complete_lifecycle_action(*args, **kwargs)


@backoff.on_exception(backoff.expo,
                      botocore.exceptions.ClientError,
                      max_tries=MAX_RETRIES,
                      giveup=no_request_limit_exceeded_code)
def describe_lifecycle_hooks(*args, **kwargs):
    return asg_client.describe_lifecycle_hooks(*args, **kwargs)


LOGGER.info('Program started')

region = get_region()
asg_client = boto3.client('autoscaling', region_name=region)
instance_id = get_instance_id()

loop = True
while loop:
    time.sleep(5)
    response = describe_auto_scaling_instances([instance_id])
    for instance in response['AutoScalingInstances']:
        lifecycle_state = instance['LifecycleState']
        asg_name = instance['AutoScalingGroupName']
        if lifecycle_state == "Terminating:Wait":
            LOGGER.info('This instance is in Terminating:Wait lyfecycle state'. format())
            deregister_runners()
            lh_name = None
            res = describe_lifecycle_hooks(AutoScalingGroupName=asg_name)
            for lhook in res['LifecycleHooks']:
                if lhook['LifecycleTransition'] == 'autoscaling:EC2_INSTANCE_TERMINATING':
                    lh_name = lhook['LifecycleHookName']
            wait_for_running_job_to_finish(lh_name, asg_name, instance_id)
            LOGGER.info('Sending complete lyfecycle action')
            r = complete_lifecycle_action(
                LifecycleHookName=lh_name,
                AutoScalingGroupName=asg_name,
                LifecycleActionResult='ABANDON',
                InstanceId=instance_id
            )
            LOGGER.debug("Response: {}".format(r))
            loop = False

LOGGER.info('Program finished')
