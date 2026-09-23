#!/bin/sh

RUNETTODAY_API_URL="${RUNETTODAY_API_URL:-https://www.runettoday.ru/api/v1}"

api_request() {
    method="$1"
    endpoint="$2"
    body="${3:-}"
    access_token="${4:-}"

    if [ -n "$body" ]; then
        if [ -n "$access_token" ]; then
            curl -fsS \
                -X "$method" \
                "$RUNETTODAY_API_URL$endpoint" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $access_token" \
                --data "$body"
        else
            curl -fsS \
                -X "$method" \
                "$RUNETTODAY_API_URL$endpoint" \
                -H "Content-Type: application/json" \
                --data "$body"
        fi
    else
        if [ -n "$access_token" ]; then
            curl -fsS \
                -X "$method" \
                "$RUNETTODAY_API_URL$endpoint" \
                -H "Authorization: Bearer $access_token"
        else
            curl -fsS \
                -X "$method" \
                "$RUNETTODAY_API_URL$endpoint"
        fi
    fi
}
