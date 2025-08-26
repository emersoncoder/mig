FROM dunglas/frankenphp:1-php8.3

# Extensões essenciais (Debian/apt, não apk)
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      libzip-dev \
      libicu-dev \
      unzip git ca-certificates; \
    docker-php-ext-install -j"$(nproc)" pdo_mysql; \
    rm -rf /var/lib/apt/lists/*
