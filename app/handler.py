import json
import os
import platform
from datetime import datetime, timezone


def lambda_handler(event, context):
    """
    Handler principal da Lambda.

    'event' contém os dados da requisição HTTP (método, path, headers, body).
    'context' contém metadados da execução (nome da função, memória, tempo restante).
    """

    path = event.get("rawPath", "/")
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")

    routes = {
        "/":        handle_root,
        "/health":  handle_health,
        "/info":    handle_info,
    }

    handler_fn = routes.get(path, handle_not_found)
    return handler_fn(event, context)


def handle_root(event, context):
    return response(200, {
        "message": "API Lambda rodando via CI/CD — deploy automático funcionando",
        "author":  "Bruno Queiroz",
        "routes": ["/", "/health", "/info"],
    })


def handle_health(event, context):
    return response(200, {
        "status":    "healthy",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })


def handle_info(event, context):
    return response(200, {
        "function_name":    context.function_name,
        "function_version": context.function_version,
        "memory_limit_mb":  context.memory_limit_in_mb,
        "remaining_time_ms": context.get_remaining_time_in_millis(),
        "environment":      os.environ.get("ENVIRONMENT", "not set"),
        "python_version":   platform.python_version(),
        "deployed_at":      os.environ.get("DEPLOYED_AT", "not set"),
    })


def handle_not_found(event, context):
    return response(404, {
        "error": "Route not found",
        "path":  event.get("rawPath", "/"),
    })


def response(status_code, body):
    """Formata a resposta no padrão que o API Gateway espera."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type":                "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, default=str),
    }
