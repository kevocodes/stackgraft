# Inside the context, so this unit's own tree is backend/orders.
FROM postgres:16-alpine
RUN apk add --no-cache netcat-openbsd curl
WORKDIR /app
COPY serve.sh /app/serve.sh
COPY orders/ /app/orders/
CMD ["sh", "/app/serve.sh", "orders", "810"]
