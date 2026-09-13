#!/bin/sh
# gcloud держит токен для vertex, ключ прилетает томом secrets
set -e

if [ -f "$VERTEX_SA_KEY_PATH" ]; then
    # ошибку раньше глушили, и разбор домашнего задания молча оставался без модели
    if error=$(gcloud auth activate-service-account --key-file="$VERTEX_SA_KEY_PATH" --quiet 2>&1); then
        echo "[entrypoint] сервисный аккаунт vertex активирован"
    else
        echo "[entrypoint] активировать сервисный аккаунт не вышло, vertex не поднимется: $error"
    fi
fi

exec "$@"
