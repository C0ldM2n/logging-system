ARG ES_VERSION

FROM docker.elastic.co/elasticsearch/elasticsearch:${ES_VERSION:-9.1.3}

USER 0
RUN microdnf install --setopt=tsflags=nodocs -y openssl && \
    microdnf clean all
USER 1000:0

ENTRYPOINT ["/entrypoint.sh"]
