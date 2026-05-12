FROM php:8.2-apache

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libgmp-dev \
    libpng-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    libzip-dev \
    libonig-dev \
    libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# Configure gd with jpeg + freetype support before installing
RUN docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg

# Install required PHP extensions
RUN docker-php-ext-install \
    gmp \
    gd \
    zip \
    soap \
    mbstring \
    pdo \
    pdo_mysql

# Enable Apache mod_rewrite
RUN a2enmod rewrite

# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Copy application source from the submodule (build context is repo root)
COPY wow-registration/ /var/www/html/
 
# Install Composer dependencies
RUN composer install --no-interaction --no-dev --optimize-autoloader \
    --working-dir=/var/www/html/application
 
# Copy custom entrypoint from the docker files folder
COPY wow-registration-docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
 
# Fix permissions
RUN chown -R www-data:www-data /var/www/html
 
EXPOSE 80
 
ENTRYPOINT ["/entrypoint.sh"]
 
