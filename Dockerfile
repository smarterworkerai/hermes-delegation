FROM debian:13-slim

ARG PZAGENT_UID=1000
ARG PZAGENT_GID=1000
ARG OPENCODE_PACKAGE=opencode-ai@latest

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Europe/Berlin \
    WORKSPACE=/workspace \
    SOURCE_ROOT=/workspace/source \
    HOME=/home/pzagent \
    PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    bash ca-certificates curl gnupg git openssh-server tmux coreutils findutils \
    procps less nano jq ripgrep unzip zip python3 python3-pip nodejs npm tzdata \
 && mkdir -p -m 755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && npm install -g "${OPENCODE_PACKAGE}" \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN groupadd --gid "${PZAGENT_GID}" pzagent \
 && useradd --uid "${PZAGENT_UID}" --gid "${PZAGENT_GID}" --create-home --home-dir /home/pzagent --shell /bin/bash pzagent \
 && mkdir -p /workspace /workspace/source /var/run/sshd /run/sshd /home/pzagent/.ssh /home/pzagent/.local/share/opencode /workspace/delegations \
 && chown -R pzagent:pzagent /workspace /home/pzagent \
 && chmod 700 /home/pzagent/.ssh

COPY sshd_config.d/hermes-worker.conf /etc/ssh/sshd_config.d/hermes-worker.conf
COPY scripts/bootstrap-worker.sh /usr/local/bin/bootstrap-worker
COPY scripts/run-delegated-task.sh /usr/local/bin/run-delegated-task
COPY scripts/collect-results.sh /usr/local/bin/collect-results
COPY scripts/cleanup-old-runs.sh /usr/local/bin/cleanup-old-runs
COPY scripts/check-worker-runtime.sh /usr/local/bin/check-worker-runtime
COPY scripts/follow-delegation.sh /usr/local/bin/follow-delegation
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/bootstrap-worker /usr/local/bin/run-delegated-task /usr/local/bin/collect-results /usr/local/bin/cleanup-old-runs /usr/local/bin/check-worker-runtime /usr/local/bin/follow-delegation \
 && ssh-keygen -A

EXPOSE 22
WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/sshd", "-D", "-e"]
