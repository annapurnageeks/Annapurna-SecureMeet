# Dockerfile
FROM nginx:alpine
COPY client/build/web /usr/share/nginx/html
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
