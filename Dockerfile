# syntax=docker/dockerfile:1.7

# =============================================================
# Stage 1: builder - instala dependências em um virtualenv
# =============================================================
FROM python:3.11-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

# Build tools necessários apenas para compilar extensões nativas.
# Não existem na imagem final.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev \
 && rm -rf /var/lib/apt/lists/*

# Virtualenv isolado que será copiado para o runtime
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /build

# Layer de dependências (muda pouco) antes do código (muda muito)
COPY requirements.txt /build/requirements.txt

RUN pip install --no-cache-dir --upgrade pip setuptools wheel \
 && pip install --no-cache-dir -r /build/requirements.txt \
 && find /opt/venv -type d -name '__pycache__' -prune -exec rm -rf {} + \
 && find /opt/venv -type f -name '*.pyc' -delete

# =============================================================
# Stage 2: runtime - somente virtualenv + código da aplicação
# =============================================================
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000 \
    PATH="/opt/venv/bin:$PATH"

# curl é a única dependência de sistema exigida pelo HEALTHCHECK
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt /tmp/*

# Usuário e grupo sem privilégios (UID/GID 1000)
RUN groupadd --gid 1000 mbauser \
 && useradd --uid 1000 --gid 1000 --no-create-home --shell /usr/sbin/nologin mbauser

WORKDIR /app

# Dependências prontas vindas do builder
COPY --from=builder --chown=mbauser:mbauser /opt/venv /opt/venv

# requirements.txt antes do código para maximizar o cache de layers
COPY --chown=mbauser:mbauser requirements.txt /app/requirements.txt

# Código da aplicação por último
COPY --chown=mbauser:mbauser app/ /app/app/

RUN chown -R mbauser:mbauser /app

USER mbauser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
    CMD curl --fail --silent --show-error http://localhost:8000/health || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
