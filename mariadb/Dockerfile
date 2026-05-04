FROM mariadb:11

COPY docker-entrypoint-wrap.sh /usr/local/bin/docker-entrypoint-wrap.sh
RUN chmod +x /usr/local/bin/docker-entrypoint-wrap.sh

ENTRYPOINT ["docker-entrypoint-wrap.sh"]
