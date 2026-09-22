#!/bin/bash
set -e
 
# --- Ler passwords a partir de Docker secrets ---
MYSQL_PASSWORD=$(cat /run/secrets/db_password)
MYSQL_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)
 
# --- Preparar diretórios e permissões ---
# Importante quando /var/lib/mysql é um volume montado do host,
# cujo dono pode não ser o utilizador "mysql" dentro do container.
mkdir -p /run/mysqld
chown -R mysql:mysql /var/lib/mysql
chown -R mysql:mysql /run/mysqld
 
# --- Inicializar só se ainda não existir base de sistema ---
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "[mariadb] Primeira execução, a inicializar base de dados..."
 
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql
 
    echo "[mariadb] A criar base de dados e utilizador (modo bootstrap)..."
 
    # --bootstrap: arranca o servidor só para ler SQL do stdin,
    # sem abrir rede nem sockets, e desliga-se sozinho no fim.
    # Evita o ciclo manual de arrancar em background / ping / shutdown.
    mariadbd --bootstrap --user=mysql --datadir=/var/lib/mysql << EOF
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF
 
    touch /var/lib/mysql/.initialized
    chown mysql:mysql /var/lib/mysql/.initialized
 
    echo "[mariadb] Inicialização concluída."
else
    echo "[mariadb] Base de dados já inicializada, a saltar setup."
fi
 
# --- Arrancar o servidor definitivo em foreground (PID 1) ---
echo "[mariadb] A arrancar MariaDB..."
exec mysqld_safe --datadir=/var/lib/mysql