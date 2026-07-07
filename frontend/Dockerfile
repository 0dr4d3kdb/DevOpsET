FROM alpine:3.19 AS builder
WORKDIR /src
COPY index.html .
COPY app.js .
COPY default.conf .

FROM nginx:alpine
COPY --from=builder /src/index.html /usr/share/nginx/html/
COPY --from=builder /src/app.js /usr/share/nginx/html/
COPY --from=builder /src/default.conf /etc/nginx/conf.d/
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
