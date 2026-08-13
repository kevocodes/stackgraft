# At its own context root, and it takes all of web/ -- correctly.
FROM alpine:latest
RUN apk add --no-cache netcat-openbsd
WORKDIR /app
COPY . /app
CMD ["sh", "/app/serve.sh", "web", "8106"]
