ARG XNAT_VERSION=1.10.2
ARG XNAT_ROOT=/data/xnat
ARG XNAT_HOME=/data/xnat/home
# default plugins for AIS
ARG container_service_ver=3.9.0
ARG ldap_auth_ver=1.3.0
ARG ohif_viewer_ver=3.8.0
ARG openid_auth_ver=1.6.0
ARG xsync_ver=1.8.1
ARG batch_launch_ver=0.9.0
ARG jupyterhub_ver=1.3.4

FROM tomcat:9.0-jdk21-temurin-noble AS build
ARG XNAT_VERSION
ARG XNAT_ROOT
ARG XNAT_HOME
# default plugins for AIS
ARG container_service_ver
ARG ldap_auth_ver
ARG ohif_viewer_ver
ARG openid_auth_ver
ARG xsync_ver
ARG batch_launch_ver
ARG jupyterhub_ver

RUN <<EOT
  apt-get update
  apt-get install -y \
    unzip \
    wget
  rm -rf /var/lib/apt/lists/*
EOT

# Setup XNAT base directory structure
RUN <<EOT
  mkdir -p \
    ${XNAT_ROOT}/archive \
    ${XNAT_ROOT}/build \
    ${XNAT_ROOT}/cache \
    ${XNAT_ROOT}/fileStore \
    ${XNAT_ROOT}/ftp \
    ${XNAT_HOME}/config/auth \
    ${XNAT_HOME}/logs \
    ${XNAT_HOME}/plugins \
    ${XNAT_HOME}/themes \
    ${XNAT_HOME}/work \
    ${XNAT_ROOT}/inbox \
    ${XNAT_ROOT}/pipeline \
    ${XNAT_ROOT}/prearchive
EOT

# Install XNAT web Java application
RUN <<EOT
  set -eu
  rm -rf ${CATALINA_HOME}/webapps/*
  mkdir -p ${CATALINA_HOME}/webapps/ROOT
  curl -fsSL -o /tmp/xnat-web-${XNAT_VERSION}.war \
    https://github.com/NrgXnat/xnat/releases/download/${XNAT_VERSION}/xnat-web-${XNAT_VERSION}.war
  unzip -o -d ${CATALINA_HOME}/webapps/ROOT /tmp/xnat-web-${XNAT_VERSION}.war
EOT

# Download standard plugins
RUN <<EOT
  set -eu
  cd ${XNAT_HOME}/plugins/
  curl -fsSL -O \
    https://github.com/NrgXnat/container-service/releases/download/${container_service_ver}/container-service-${container_service_ver}-fat.jar
  curl -fsSL -O \
    https://github.com/NrgXnat/ldap-auth-plugin/releases/download/${ldap_auth_ver}/ldap-auth-plugin-${ldap_auth_ver}.jar
  curl -fsSL -O \
    https://github.com/xnatworks/ohif-viewer-xnat-plugin/releases/download/${ohif_viewer_ver}/ohif-viewer-${ohif_viewer_ver}-fat.jar
  curl -fsSL -O \
    https://github.com/NrgXnat/openid-auth-plugin/releases/download/${openid_auth_ver}/openid-auth-plugin-${openid_auth_ver}-xpl.jar
  curl -fsSL -O \
    https://github.com/NrgXnat/xsync/releases/download/${xsync_ver}/xsync-plugin-all-${xsync_ver}.jar
  curl -fsSL -O \
    https://github.com/NrgXnat/batch-launch-plugin/releases/download/${batch_launch_ver}/batch-launch-${batch_launch_ver}-xpl.jar
  curl -fsSL -O \
    https://github.com/NrgXnat/xnat-jupyterhub-plugin/releases/download/v${jupyterhub_ver}/xnat-jupyterhub-plugin-${jupyterhub_ver}.jar
EOT

FROM tomcat:9.0-jdk21-temurin-noble
ARG XNAT_VERSION
ARG XNAT_ROOT
ARG XNAT_HOME

RUN <<EOT
  apt update
  apt install -y \
    less \
    telnet \
    vim \
    dcmtk
  rm -rf /var/lib/apt/lists/*
  rm -rf ${CATALINA_HOME}/webapps/*
EOT

# -----------------------------------------------------------------------------
# OpenCV native for dcm4che's image codecs.
# Reference: https://github.com/NrgXnat/xnat/blob/1.10.2/Dockerfile
#
# dcm4che 5 decodes JPEG-family pixel data with the ImageIO readers in
# org.dcm4che:dcm4che-imageio-opencv, which call this library. Without it, snapshots, thumbnails,
# montages and alterPixels redaction of JPEG-family data fail with
# "UnsatisfiedLinkError: 'long org.opencv.core.Mat.n_Mat(int, int, int)'", and Native DICOM
# Pre-Compression is skipped. "No Reader for format: jpeg2000-cv registered" means the jar is
# missing, not this library.
#
# /usr/java/packages/lib is already on the JVM's default java.library.path on Linux, so nothing
# needs -Djava.library.path.
#
# Set INSTALL_OPENCV=false for 1.9.x builds, which are on dcm4che 2 and would carry ~19 MB unused.
# -----------------------------------------------------------------------------
ARG INSTALL_OPENCV=true
# No default: BuildKit populates TARGETARCH with the architecture actually being built for, and a
# default here would mask it -- an arm64 build would silently install the amd64 native. Empty (a
# pre-BuildKit builder) falls through to the error case, which is the right answer.
ARG TARGETARCH
ARG OPENCV_VERSION=5.0.0-dcm
ARG OPENCV_BASE=https://nrgxnat.jfrog.io/nrgxnat/libs-release/org/weasis/thirdparty/org/opencv/libopencv_java/${OPENCV_VERSION}
RUN <<EOT
  set -eu
  if [ "${INSTALL_OPENCV}" != "true" ]; then
    echo "INSTALL_OPENCV=${INSTALL_OPENCV}, skipping the OpenCV native"
    exit 0
  fi
  case "${TARGETARCH}" in
    amd64) classifier=linux-x86-64;  sha256=3552c806744192c734f6cf492bf95a139cbfd6f800ff662688d18b6a199f92f1 ;;
    arm64) classifier=linux-aarch64; sha256=b07190e6ef6e233c2b7dc7f945c5b470be44450a49f9915aeaaa86f8799ef6a0 ;;
    *) echo "No OpenCV native published for TARGETARCH=${TARGETARCH}" >&2; exit 1 ;;
  esac
  mkdir -p /usr/java/packages/lib
  curl -fsSL --retry 3 -o /usr/java/packages/lib/libopencv_java.so \
    "${OPENCV_BASE}/libopencv_java-${OPENCV_VERSION}-${classifier}.so"
  echo "${sha256}  /usr/java/packages/lib/libopencv_java.so" | sha256sum -c -
EOT

COPY --from=build ${CATALINA_HOME}/webapps/ ${CATALINA_HOME}/webapps/
COPY --from=build ${XNAT_ROOT} ${XNAT_ROOT}

RUN <<EOT
  sed -i \
    's/ch.qos.logback.core.rolling.RollingFileAppender/ch.qos.logback.core.ConsoleAppender/' \
    ${CATALINA_HOME}/webapps/ROOT/WEB-INF/classes/logback.xml
EOT

COPY --chmod=0755 ./entrypoint.sh /usr/local/bin/entrypoint.sh
RUN mkdir -p /docker-entrypoint.d
COPY ./xnat-conf.properties ${XNAT_HOME}/config/xnat-conf.properties

ENV XNAT_HOME=${XNAT_HOME} \
    XNAT_VERSION=${XNAT_VERSION} \
    TZ=UTC \
    CATALINA_OPTS="-XX:InitialRAMPercentage=40.0 -XX:MaxRAMPercentage=50.0 -XX:+UseG1GC -XX:-OmitStackTraceInFastThrow -Dxnat.home=${XNAT_HOME}"

LABEL org.opencontainers.image.source https://github.com/australian-imaging-service/xnat-docker-build
LABEL maintainer="AIS Team"

ENTRYPOINT ["entrypoint.sh"]
CMD ["catalina.sh","run"]
