# This docker file will build on the jenkins-agent to provide access to npm utilities
ARG IMAGE_VERSION_ARG=latest

FROM awharn/jenkins-agent:latest

USER root

ARG IMAGE_VERSION_ARG
ARG DEFAULT_NODE_VERSION=${IMAGE_VERSION_ARG:-12}

ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

# Add node version 12 which should bring in npm, add maven and build essentials and required ssl certificates to contact maven central
# expect is also installed so that you can use that to login to your npm registry if you need to
# Note: we'll install Node.js globally and include the build tools for pyhton - but nvm will override when the container starts
RUN curl -sL "https://deb.nodesource.com/setup_$DEFAULT_NODE_VERSION.x" | sudo -E bash -
RUN apt-get install -y nodejs expect build-essential maven ca-certificates-java && update-ca-certificates -f

# Install nvm to enable multiple versions of node runtime and define environment 
# variable for setting the desired node js version (defaulted to "current" for Node.js)
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash

# dd the jenkins users
RUN groupadd npmusers \
  && usermod -aG npmusers jenkins 

# Also install nvm for user jenkins
USER jenkins
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
USER root

# Get rid of dash and use bash instead
RUN echo "dash dash/sh boolean false" | debconf-set-selections
RUN DEBIAN_FRONTEND=noninteractive dpkg-reconfigure dash

ARG tempDir=/tmp/jenkins-npm-agent
ARG sshEnv=/etc/profile.d/npm_setup.sh
ARG bashEnv=/etc/bash.bashrc

# First move the template file over
RUN mkdir ${tempDir}
COPY env.bashrc ${tempDir}/env.bashrc
# COPY env.bashrc /usr/local/env.sh

# Next, make the file available to all to read and source
# RUN chmod +r /usr/local/env.sh
ENV ENV=${bashEnv}

# Create a shell file that applies the configuration for sessions. (anything not bash really)
RUN touch ${sshEnv} \
    && echo '#!bin/sh'>>${sshEnv} \
    && cat ${tempDir}/env.bashrc>>${sshEnv}

# Create a properties file that is used for all bash sessions on the machine
# Add the environment setup before the exit line in the global bashrc file
RUN sed -i -e "/# If not running interactively, don't do anything/r ${tempDir}/env.bashrc" -e //N ${bashEnv}

# Cleanup after ourselves
RUN rm -rdf ${tempDir}

# Copy the setup script and node/nvm scripts for execution (allow anyone to run them)
ARG scriptsDir=/usr/local/bin/
COPY docker-entrypoint.sh ${scriptsDir}
COPY install_node.sh ${scriptsDir}

RUN install_node.sh ${DEFAULT_NODE_VERSION}
RUN su -c "install_node.sh ${DEFAULT_NODE_VERSION}" - jenkins

RUN apt-get -q autoremove && apt-get -q clean -y && rm -rf /var/lib/apt/lists/* && rm -f /var/cache/apt/*.bin

# Execute the setup script when the image is run. Setup will install the desired version via 
# nvm for both the root user and jenkins - then start the ssh service
ENTRYPOINT ["docker-entrypoint.sh"]

# Default to exec ssh
CMD ["/usr/sbin/sshd", "-D"]

