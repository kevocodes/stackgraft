# Inside the context, so this unit's own tree is backend/search.
FROM postgres:16-alpine
RUN apk add --no-cache netcat-openbsd curl
WORKDIR /app
COPY serve.sh /app/serve.sh
COPY search/ /app/search/
CMD ["sh", "/app/serve.sh", "search", "810"]
