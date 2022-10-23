# syntax=docker/dockerfile:1
FROM ubuntu:kinetic

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get -qq update
RUN apt-get -qq upgrade
RUN apt-get -qq install sudo curl git
RUN useradd -m jason && \
    usermod -aG sudo jason && \
    echo "jason ALL=NOPASSWD: ALL" >> /etc/sudoers


COPY ./install.sh /sysgit/install.sh

COPY ./test-config-repo /sysgit/test-config-repo
RUN cd /sysgit/test-config-repo; \
    git init; \
    git add .; \
    git config --global user.email "test@example.com"; \
    git config --global user.name "Test"; \
    git commit -m "Initial commit"

USER jason
ENV NONINTERACTIVE=1
ENV SYSGIT_CONFIG_REPO="file:///sysgit/test-config-repo/.git"
#RUN sudo apt-get -qq clean autoclean && sudo apt-get -qq autoremove --yes && rm -rf /var/lib/{apt,dpkg,cache,log}/

ENTRYPOINT ["/bin/bash", "-c", "/sysgit/install.sh; /bin/bash -"]

