# Inside the context, so this unit's own tree is backend/billing.
FROM postgres:16-alpine
RUN apk add --no-cache netcat-openbsd curl
WORKDIR /app
COPY serve.sh /app/serve.sh
COPY billing/ /app/billing/
CMD ["sh", "/app/serve.sh", "billing", "810"]
