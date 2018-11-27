mkdir -p /etc/gitlab-runner
cat > /etc/gitlab-runner/config.toml <<- EOF

${runners_config}

EOF

curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh | bash
yum install gitlab-runner-${gitlab_runner_version} -y
curl -L https://github.com/docker/machine/releases/download/v${docker_machine_version}/docker-machine-`uname -s`-`uname -m` >/tmp/docker-machine && \
  chmod +x /tmp/docker-machine && \
  cp /tmp/docker-machine /usr/local/bin/docker-machine && \
  ln -s /usr/local/bin/docker-machine /usr/bin/docker-machine

service gitlab-runner restart
chkconfig gitlab-runner on

export token=$(curl --request POST -L "${gitlab_runner_coordinator_url_with_trailing_slash}api/v4/runners" \
    --form "token=${gitlab_runner_registration_token}" \
    --form "tag_list=${gitlab_runner_tag_list}" \
    --form "description=${giltab_runner_description}" \
    --form "locked=${gitlab_runner_locked_to_project}" \
    --form "run_untagged=${gitlab_runner_run_untagged}" \
    --form "maximum_timeout=${gitlab_runner_maximum_timeout}" \
    | jq -r .token)

sed -i.bak s/__REPLACED_BY_USER_DATA__/$token/g /etc/gitlab-runner/config.toml
export token=""