#!/bin/bash

YUM_CMD=$(which yum)
APT_GET_CMD=$(which apt-get)

ARCH="$(uname -m)"
if [[ "$${ARCH}" == "x86_64" ]]; then
  ARCH="amd64"
fi

if [[ "${runner_version}" == "latest" || -z "${runner_version}" ]]; then
    runner_version=""
    runner_version_path="latest"
else
    runner_version="-${runner_version}"
    runner_version_path="v${runner_version}"
fi

if [[ ! -z $${YUM_CMD} ]]; then
  yum update -y
  yum install -y curl jq
  # The package for redhat don't seem to exist (see https://gitlab.com/gitlab-org/gitlab-runner/-/issues/25554), follow https://docs.gitlab.com/runner/install/linux-manually.html
  if [ -r '/etc/redhat-release' ]; then
    yum install -y python-pip docker git
    curl -LJO "https://gitlab-runner-downloads.s3.amazonaws.com/$${runner_version_path}/rpm/gitlab-runner_$${ARCH}.rpm"
    rpm -i "gitlab-runner_$${ARCH}.rpm"
    curl -LJO https://s3.amazonaws.com/amazoncloudwatch-agent/redhat/$${ARCH}/latest/amazon-cloudwatch-agent.rpm
    rpm -i amazon-cloudwatch-agent.rpm
    rm -f "gitlab-runner_$${ARCH}.rpm" amazon-cloudwatch-agent.rpm
  else
    curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh | sudo bash
    yum install -y gitlab-runner$${runner_version} python-pip awslogs docker git
  fi
elif [[ ! -z $${APT_GET_CMD} ]]; then
  apt-get update
  apt-get upgrade -y
  apt-get install -y curl jq
  curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
  curl -LJO https://s3.amazonaws.com/amazoncloudwatch-agent/debian/$${ARCH}/latest/amazon-cloudwatch-agent.deb
  dpkg -i -E amazon-cloudwatch-agent.deb
  rm -f amazon-cloudwatch-agent.deb
  apt-get install -y gitlab-runner$${runner_version} python3-pip python-is-python3 docker.io git
else
  echo "OS not supported $(cat /etc/*release | grep '^ID=')"
  exit 1;
fi

pip install boto3 backoff

systemctl enable docker.service
systemctl start docker.service

INSTANCE_ID="$(curl http://169.254.169.254/latest/meta-data/local-ipv4)"

token="$(aws ssm get-parameters --names ${runner_token_ssm_path} --with-decryption --query 'Parameters[0].Value' --output text --region ${region})"

%{ if runner_registration_type == "legacy" ~}
for i in ${num_runners}; do
  sudo gitlab-runner register \
    --non-interactive \
    --url "${gitlab_url}" \
    --registration-token "$${token}" \
    ${executor} \
    --maintenance-note "Free-form maintainer notes about this runner" \
    --tag-list "${runner_job_tags}" \
    --run-untagged="true" \
    --locked="false" \
    --access-level="not_protected"
done
%{ else ~}
# Inspired from:
# https://docs.gitlab.com/runner/register/#register-a-runner-created-in-the-ui-with-an-authentication-token
# https://about.gitlab.com/blog/2023/07/06/how-to-automate-creation-of-runners/

%{ if runner_registration_type == "authentication-token-group-creation" ~}
token=$( curl -sX POST "${gitlab_url}/api/v4/user/runners" \
    --data runner_type=project_type \
    --data "project_id=${project_id}" \
    --data "tag_list=${runner_job_tags}" \
    --header "PRIVATE-TOKEN: $${token}" | jq -r '.token' )

%{ endif ~}
for i in ${num_runners}; do
  sudo gitlab-runner register \
    --non-interactive \
    --url "${gitlab_url}" \
    --token "$${token}" \
    ${executor}
done
%{ endif ~}

%{ if executor_type == "shell" ~}
# Ensure the gitlab runner has sudo permissions if needed for the shell runner.
# Docker runner doesn't need as commands are run inside docker containers
echo "gitlab-runner ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
%{ endif ~}

mkdir -p /etc/awslogs
cat > /etc/awslogs/awscli.conf << EOF
[plugins]
cwlogs = cwlogs
[default]
region = ${region}
EOF

cat > /etc/awslogs/awslogs.conf << EOF
[general]
state_file = /var/lib/awslogs/agent-state

[/var/log/cloud-init-output.log]
datetime_format = %b %d %H:%M:%S
file = /var/log/cloud-init-output.log
buffer_duration = 5000
log_stream_name = {instance_id} - {ip_address} - cloud-init-output
initial_position = start_of_file
log_group_name = ${log_group}

[/var/log/hookchecker]
datetime_format = %b %d %H:%M:%S
file = /var/log/hookchecker.log
buffer_duration = 5000
log_stream_name = {instance_id} - {ip_address} - hookchecker
initial_position = start_of_file
log_group_name = ${log_group}
EOF

cat > /usr/bin/hookchecker << EOF
${hookchecker_py_content}
EOF

cat > /etc/systemd/system/hookchecker.service << EOF
${hookchecker_service_content}
EOF

if [[ ! -z $${YUM_CMD} ]]; then
  if [ -r '/etc/redhat-release' ]; then
    sudo systemctl enable amazon-cloudwatch-agent.service
    sudo service amazon-cloudwatch-agent start
  fi
  sudo service awslogsd start
  sudo systemctl enable awslogsd
elif [[ ! -z $${APT_GET_CMD} ]]; then
  sudo systemctl enable amazon-cloudwatch-agent.service
  sudo service amazon-cloudwatch-agent start
fi

chmod +x /usr/bin/hookchecker
sudo systemctl start hookchecker
