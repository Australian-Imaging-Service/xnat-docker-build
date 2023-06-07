FROM tomcat:9.0.62-jdk8-openjdk-bullseye

ARG XNAT_VERSION=1.8.8
ARG XNAT_ROOT=/data/xnat
ARG XNAT_HOME=/data/xnat/home
ARG XNAT_DATASOURCE_DRIVER=org.postgresql.Driver
ARG XNAT_DATASOURCE_URL=jdbc:postgresql://xnat-postgresql/xnat
ARG XNAT_DATASOURCE_USERNAME=xnat
ARG XNAT_DATASOURCE_PASSWORD=xnat
ARG XNAT_SMTP_ENABLED=false
ARG TOMCAT_XNAT_FOLDER=ROOT
ARG TOMCAT_XNAT_FOLDER_PATH=${CATALINA_HOME}/webapps/${TOMCAT_XNAT_FOLDER}
ARG XNAT_MIN_HEAP=2000m
ARG XNAT_MAX_HEAP=2000m

# default plugins for AIS
ARG container_service_ver=3.3.1-fat
ARG ldap_auth_ver=1.1.0
ARG ohif_viewer_ver=3.5.1-XNAT-1.8.7
ARG openid_auth_ver=1.2.0-SNAPSHOT
ARG xsync_ver=1.5.0
ARG batch_launch_ver=0.6.0

# default environment variables
ENV CATALINA_OPTS="-Xms${XNAT_MIN_HEAP} -Xmx${XNAT_MAX_HEAP} -Dxnat.home=${XNAT_HOME}"
ENV XNAT_HOME=${XNAT_HOME}

ADD make-xnat-config.sh /usr/local/bin/make-xnat-config.sh
ADD entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod u+x /usr/local/bin/*.sh

RUN apt-get update && apt-get install -y postgresql-client wget telnet less

RUN rm -rf ${CATALINA_HOME}/webapps/*
RUN mkdir -p \
        ${TOMCAT_XNAT_FOLDER_PATH} \
        ${XNAT_HOME}/config \
        ${XNAT_HOME}/logs \
        ${XNAT_HOME}/plugins \
        ${XNAT_HOME}/work \
        ${XNAT_ROOT}/archive \
        ${XNAT_ROOT}/build \
        ${XNAT_ROOT}/cache \
        ${XNAT_ROOT}/ftp \
        ${XNAT_ROOT}/pipeline \
        ${XNAT_ROOT}/prearchive
RUN /usr/local/bin/make-xnat-config.sh
RUN rm /usr/local/bin/make-xnat-config.sh
RUN wget --no-verbose --output-document=/tmp/xnat-web-${XNAT_VERSION}.war https://api.bitbucket.org/2.0/repositories/xnatdev/xnat-web/downloads/xnat-web-${XNAT_VERSION}.war
RUN unzip -o -d ${TOMCAT_XNAT_FOLDER_PATH} /tmp/xnat-web-${XNAT_VERSION}.war
RUN rm -f /tmp/xnat-web-${XNAT_VERSION}.war
RUN sed -i 's/ch.qos.logback.core.rolling.RollingFileAppender/ch.qos.logback.core.ConsoleAppender/' ${TOMCAT_XNAT_FOLDER_PATH}/WEB-INF/classes/logback.xml

# Download standard plugins
RUN wget --no-verbose -O container-service-${container_service_ver}.jar https://api.bitbucket.org/2.0/repositories/xnatdev/container-service/downloads/container-service-${container_service_ver}.jar
RUN wget --no-verbose -O ldap-auth-plugin-${ldap_auth_ver}.jar https://api.bitbucket.org/2.0/repositories/xnatx/ldap-auth-plugin/downloads/ldap-auth-plugin-${ldap_auth_ver}.jar
RUN wget --no-verbose -O ohif-viewer-${ohif_viewer_ver}.jar https://api.bitbucket.org/2.0/repositories/icrimaginginformatics/ohif-viewer-xnat-plugin/downloads/ohif-viewer-${ohif_viewer_ver}.jar
RUN wget --no-verbose -O openid-auth-plugin-${openid_auth_ver}.jar https://github.com/Australian-Imaging-Service/openid-auth-plugin/releases/download/${openid_auth_ver}/openid-auth-plugin-${openid_auth_ver}.jar
RUN wget --no-verbose -O xsync-plugin-all-${xsync_ver}.jar https://api.bitbucket.org/2.0/repositories/xnatdev/xsync/downloads/xsync-plugin-all-${xsync_ver}.jar
RUN wget --no-verbose -O batch-launch-${batch_launch_ver}.jar https://api.bitbucket.org/2.0/repositories/xnatx/xnatx-batch-launch-plugin/downloads/batch-launch-${batch_launch_ver}.jar
RUN mv *.jar ${XNAT_HOME}/plugins/

ENV XNAT_HOME=${XNAT_HOME} XNAT_DATASOURCE_USERNAME=${XNAT_DATASOURCE_USERNAME} PGPASSWORD=${XNAT_DATASOURCE_PASSWORD}

LABEL org.opencontainers.image.source https://github.com/australian-imaging-service/xnat-build
LABEL maintainer="AIS Team ais-team@ais"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh", "/usr/local/tomcat/bin/catalina.sh", "run"]
USER 0

