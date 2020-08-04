#!/bin/bash
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh | sudo bash
sudo yum install -y gitlab-runner python-pip awslogs
pip install boto3
pip install backoff

INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
NUM_RUNNERS=${num_runners}

for i in $NUM_RUNNERS
do
	sudo gitlab-runner register \
  --non-interactive \
  --url "${gitlab_url}" \
  --registration-token "${registration_token}" \
  --executor "shell" \
  --description "shell-runner $INSTANCE_ID" \
  --tag-list "aws" \
  --run-untagged="true" \
  --locked="false" \
  --access-level="not_protected"
done

cat > /etc/awslogs/awscli.conf << EOF
[plugins]
cwlogs = cwlogs
[default]
region = ${region}
EOF

cat > /etc/awslogs/awslogs.conf << EOF
[general]
state_file = /var/lib/awslogs/agent-state

[/var/log/hookchecker]
datetime_format = %b %d %H:%M:%S
file = /var/log/hookchecker.log
buffer_duration = 5000
log_stream_name = {instance_id} - {ip_address}
initial_position = start_of_file
log_group_name = /gitlab/runner/logs
EOF

cat > /usr/bin/hookchecker << EOF
${hookchecker_py_content}
EOF

cat > /etc/systemd/system/hookchecker.service << EOF
${hookchecker_service_content}
EOF

sudo service awslogsd start
sudo systemctl enable awslogsd

chmod +x /usr/bin/hookchecker
sudo systemctl start hookchecker