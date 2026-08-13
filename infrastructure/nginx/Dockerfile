ARG NGINX_IMAGE=nginx:1.30.4-alpine
FROM ${NGINX_IMAGE}

COPY infrastructure/nginx/templates /etc/nginx/templates/petroscope
COPY infrastructure/nginx/nginx-tls-entrypoint.sh /usr/local/bin/nginx-tls-entrypoint.sh

RUN chmod 0555 /usr/local/bin/nginx-tls-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/nginx-tls-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
