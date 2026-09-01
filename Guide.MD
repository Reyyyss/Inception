# Guia Inception (42) — Passo a Passo

## 0. Estrutura de pastas

Cria isto primeiro, na raiz do projeto:

```
inception/
├── Makefile
└── srcs/
    ├── docker-compose.yml
    ├── .env
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── conf/
        │   └── tools/
        ├── wordpress/
        │   ├── Dockerfile
        │   ├── conf/
        │   └── tools/
        └── nginx/
            ├── Dockerfile
            ├── conf/
            └── tools/
```

Comandos:
```bash
mkdir -p inception/srcs/requirements/{mariadb,wordpress,nginx}/{conf,tools}
touch inception/srcs/docker-compose.yml inception/srcs/.env inception/Makefile
```

---

## 1. MariaDB (começa por aqui — é o serviço mais isolado)

### Objetivo
Container com MariaDB a correr em foreground, com uma base de dados e utilizador criados automaticamente para o WordPress, usando variáveis de ambiente (nada de passwords hardcoded).

### Passos
1. Escrever `requirements/mariadb/Dockerfile`:
   - `FROM debian:bookworm` (ou a base pedida no subject)
   - `RUN apt-get update && apt-get install -y mariadb-server`
   - `COPY` um script de entrypoint (`tools/entrypoint.sh` ou similar)
   - `ENTRYPOINT` a apontar para esse script
2. Escrever o script de entrypoint:
   - Inicializar o diretório de dados do MariaDB se ainda não existir
   - Arrancar o `mysqld` temporariamente em background só para configurar
   - Criar a base de dados do WordPress, o utilizador, dar permissões, definir password root
   - Parar o processo temporário
   - No fim, arrancar `mysqld` em **foreground** (isto é o processo PID 1, não pode ser um `&` nem `tail -f`)
3. Definir variáveis no `.env` (nomes sugeridos, ajusta ao teu gosto):
   - `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD`
4. Testar isoladamente:
   ```bash
   docker build -t mariadb ./srcs/requirements/mariadb
   docker run --env-file srcs/.env mariadb
   ```

### Como saber que está a funcionar
Consegues fazer `docker exec -it <container> mysql -u <user> -p` e ver a base de dados listada.

---

## 2. WordPress + php-fpm

### Objetivo
Container com `php-fpm` (sem nginx embutido) a correr o WordPress, instalado e configurado via `wp-cli` (sem passar pelo browser).

### Passos
1. Escrever `requirements/wordpress/Dockerfile`:
   - Base + instalar `php-fpm`, extensões PHP necessárias (mysqli, etc.), `curl`, `wp-cli`
2. Script de entrypoint:
   - Esperar/confirmar que a MariaDB está acessível (cuidado: `depends_on` não garante isto sozinho)
   - Descarregar o WordPress (`wp core download`) se ainda não existir no volume
   - Criar o `wp-config.php` com as credenciais da base de dados (via `wp config create` usando variáveis de ambiente)
   - Instalar o WordPress via `wp core install` (site title, admin user, admin password — tudo por variáveis de ambiente, não hardcoded)
   - No fim, arrancar `php-fpm` em **foreground**
3. Configurar o `php-fpm` para escutar na porta **9000**, aberta só dentro da rede interna do Docker (não exposta ao host)
4. Variáveis extra no `.env`: `WP_TITLE`, `WP_ADMIN_USER`, `WP_ADMIN_PASSWORD`, `WP_ADMIN_EMAIL`, etc.

### Como saber que está a funcionar
`docker logs` sem erros de conexão à base de dados, e o `php-fpm` a ficar "up" sem crashar.

---

## 3. NGINX

### Objetivo
Único ponto de entrada do projeto, a servir HTTPS na porta 443, com TLS 1.2/1.3, a fazer proxy do PHP para o WordPress.

### Passos
1. Escrever `requirements/nginx/Dockerfile`:
   - Base + instalar `nginx` e `openssl`
2. Gerar certificado TLS auto-assinado (podes fazer isto no `Dockerfile` com `RUN openssl req ...` ou num script)
3. Escrever `conf/nginx.conf`:
   - `listen 443 ssl;`
   - `ssl_protocols TLSv1.2 TLSv1.3;`
   - `server_name` com o teu login (ex: `login.42.fr`)
   - `location ~ \.php$ { fastcgi_pass wordpress:9000; ... }`
4. `ENTRYPOINT` a correr `nginx -g "daemon off;"` (foreground, não daemon)

### Como saber que está a funcionar
Consegues aceder a `https://localhost` (ou ao domínio configurado) e ver o WordPress a carregar.

---

## 4. Juntar tudo no `docker-compose.yml`

1. Definir os 3 `services` (mariadb, wordpress, nginx), cada um com `build: context`
2. Definir uma `network` custom (bridge) e ligar os 3 serviços a ela
3. Definir `volumes` como **bind mounts** para os dados persistirem no host (verifica o caminho exigido pelo subject, normalmente algo tipo `/home/<login>/data/...`)
4. `env_file: .env` em cada serviço
5. `restart: unless-stopped` (ou `always`) em cada serviço
6. Só o NGINX deve ter `ports: - "443:443"` — os outros não expõem portas ao host

---

## 5. Makefile (opcional mas recomendado)

Comandos úteis para automatizar:
- `make` / `make up` → `docker compose -f srcs/docker-compose.yml up --build -d`
- `make down` → `docker compose -f srcs/docker-compose.yml down`
- `make clean` → down + remover volumes/imagens
- `make re` → clean + up

---

## 6. Testar tudo incrementalmente

**Não** deixes para testar só no fim. Ordem sugerida:
1. Sobe só a MariaDB, confirma que a base de dados existe
2. Sobe MariaDB + WordPress, confirma via logs que o `wp-config.php` foi criado e o WordPress instalado
3. Sobe os 3 juntos, acede via browser em `https://<teu-domain>`

---

## 7. Checklist final antes da defesa

- [ ] Nenhuma imagem usa tag `latest`
- [ ] Nenhum container usa `tail -f`, `sleep infinity` ou hacks para ficar vivo
- [ ] Cada serviço tem o seu próprio Dockerfile (não docker-compose a puxar imagens prontas do Docker Hub, exceto a imagem base permitida)
- [ ] Passwords não estão hardcoded em nenhum Dockerfile (usar `.env` / secrets)
- [ ] `.env` está no `.gitignore` (não vai para o repositório)
- [ ] Só a porta 443 está exposta ao host
- [ ] Containers reiniciam sozinhos em caso de crash
- [ ] Volumes com bind mount no caminho correto exigido pelo subject
- [ ] `docker-compose.yml` não usa `network: host` nem `links:`
- [ ] WordPress instalado via `wp-cli`, sem passar pelo setup no browser

---

## Notas
- Sempre que tiveres uma dúvida específica (ex: "como escrevo o entrypoint da MariaDB", "erro X no NGINX"), pergunta diretamente que aprofundamos essa parte.
- Relê o subject oficial da tua sessão/campus antes de começares cada secção — alguns requisitos (nomes de variáveis, caminhos de volumes, domínio) variam.