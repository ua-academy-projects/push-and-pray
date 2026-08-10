FROM nginx:1-alpine-slim@sha256:45b82ed5f285b90d63df07ba70430fdd8f25624b416617d9e6dc93412b2006dc

COPY public/ /usr/share/nginx/html/
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
EXPOSE 80 443
