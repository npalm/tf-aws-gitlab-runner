mkdir -p /etc/gitlab-runner
cat > /etc/gitlab-runner/config.toml <<- EOF

${runners_config}

EOF

${pre_install}

if [[ `echo ${runners_executor}` == "docker" ]]
then
  yum install docker -y
  usermod -a -G docker ec2-user
  service docker start
fi

curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh | bash
yum install gitlab-runner-${gitlab_runner_version} -y
curl  --fail --retry 6 -L https://github.com/docker/machine/releases/download/v${docker_machine_version}/docker-machine-`uname -s`-`uname -m` >/tmp/docker-machine && \
  chmod +x /tmp/docker-machine && \
  cp /tmp/docker-machine /usr/local/bin/docker-machine && \
  ln -s /usr/local/bin/docker-machine /usr/bin/docker-machine

# Create a dummy machine so that the cert is generated properly
# See: https://gitlab.com/gitlab-org/gitlab-runner/issues/3676
# See: https://github.com/docker/machine/issues/3845#issuecomment-280389178
export USER=root
export HOME=/root
docker-machine create --driver none --url localhost dummy-machine
docker-machine rm -y dummy-machine
unset HOME
unset USER

# Install jq if not exists
if ! [ -x "$(command -v jq)" ]; then
  yum install jq -y
fi

token=$(aws ssm get-parameters --names "${secure_parameter_store_runner_token_key}" --with-decryption --region "${secure_parameter_store_region}" | jq -r ".Parameters | .[0] | .Value")
if [[ `echo ${runners_token}` == "__REPLACED_BY_USER_DATA__" && `echo $token` == "null" ]]
then
  token=$(curl --request POST -L "${runners_gitlab_url}/api/v4/runners" \
    --form "token=${gitlab_runner_registration_token}" \
    --form "tag_list=${gitlab_runner_tag_list}" \
    --form "description=${giltab_runner_description}" \
    --form "locked=${gitlab_runner_locked_to_project}" \
    --form "run_untagged=${gitlab_runner_run_untagged}" \
    --form "maximum_timeout=${gitlab_runner_maximum_timeout}" \
    --form "access_level=${gitlab_runner_access_level}" \
    | jq -r .token)
  aws ssm put-parameter --overwrite --type SecureString  --name "${secure_parameter_store_runner_token_key}" --value="$token" --region "${secure_parameter_store_region}"
fi

sed -i.bak s/__REPLACED_BY_USER_DATA__/`echo $token`/g /etc/gitlab-runner/config.toml

# A small script to remove this runner from being registered with Gitlab. 
cat <<REM > /etc/rc.d/init.d/remove_gitlab_registration
#!/bin/bash
# chkconfig: 35 99 03
# description: cleans up gitlab runner key
# processname: remove_runner_key
#              /etc/rc.d/init.d/remove_gitlab_registration
lockfile=/var/lock/subsys/remove_runner_key


start() {
    touch $lockfile
}

stop() {
    echo -n "Removing Gitlab Runner Token"
    aws ssm put-parameter --overwrite --type SecureString  --name "${secure_parameter_store_runner_token_key}" --region "${secure_parameter_store_region}" --value="null" && \
        curl --request DELETE "${runners_gitlab_url}/api/v4/runners" --form "token=$token"
    retval=$?
    [ $retval -eq 0 ] && rm -f $lockfile
    return $retval
}

restart() {}

reload() {}

status() {}

case "$1" in
    start)
        $1
        ;;
    stop)
        $1
        ;;
    restart)
        $1
        ;;
    status)
        $1
        ;;
    *)
        echo "Usage: $0 {start|stop|status|restart}"
        exit 2
        ;;
REM

# Symlink the script into the runlevel 0 (shutdown) and 6 (reboot) directories
# This way we'll not be assigned jobs if we're shutting down, and clean up in Gitlab.
chmod a+x /etc/init.d/remove_gitlab_registration
chkconfig --add remove_gitlab_registration

${post_install}

service gitlab-runner restart
chkconfig gitlab-runner on
