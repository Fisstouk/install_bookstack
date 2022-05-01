#!/bin/bash

# Nom		: Installation de BookStack 
# Description	: Script pour une installation en locale
# Version	: 1.0
# Auteur	: lyronn

# Affiche les commandes realisees
set -x

# Arrete le script des qu'une erreur survient
set -e

function nginx_install()
{
	# Modifie temporairement le umask
	# Après l'installation de cheat
	# umask 0022

	# Mise a jour et installation de nginx et git
	apt update -y
	apt install nginx -y
	apt install git -y

	# Demarrer le service nginx et l'activer a chaque demarrage
	systemctl start nginx.service
	systemctl enable nginx.service
}

function mariadb_install()
{
	apt install mariadb-server -y
	systemctl start mysql.service
	systemctl enable mysql.service
}

function configure_mariadb()
{
	# Creation de la bdd
	mysql -e "CREATE DATABASE bookstack;"

	# Creation de l'utilisateur bookstackuser
	mysql -e 'CREATE USER "bookstackuser"@"localhost" IDENTIFIED BY "password";'

	# Attribution des droits admin a bookstackuser
	mysql -e 'GRANT ALL PRIVILEGES ON bookstack.* TO "bookstackuser"@"localhost" IDENTIFIED BY "password" WITH GRANT OPTION;'

	# Mets à jour les modifications
	mysql -e "FLUSH PRIVILEGES;"

}

function php_install()
{
	apt install php-fpm -y

	# Demarrer php
	systemctl start php7.4-fpm.service
	systemctl enable php7.4-fpm.service

	# Installation des extensions php suivantes
	# MBstring
	apt install php7.4-mbstring -y

	# Tokenizer
	apt install php-tokenizer -y

	# GD
	apt install php-gd -y

	# MySQL
	apt install php-mysql -y

	# SimpleXML remplacé par php-xml et DOM
	apt install php-xml -y

}

function configure_composer()
{	
	# Installatin de unzip
	apt install unzip -y

	# Installation de composer
	php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"

	# Verification du hash
	php -r "if (hash_file('sha384', 'composer-setup.php') === '55ce33d7678c5a611085589f1f3ddf8b3c52d662cd01d4ba75c0ee0459970c2200a51f492d557530c71c15d8dba01eae') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"

	php composer-setup.php

	php -r "unlink('composer-setup.php');"

	# Deplace le fichier composer.phar dans /usr/local/bin/composer pour executer composer
	mv -v composer.phar /usr/local/bin/composer

	# Installe php-curl pour mettre a jour composer
	apt install php7.4-curl -y

	# Cree le fichier composer.json pour demarrer un projet
	# Les quotes permettent de protéger le EOF et d'insérer l'étoile
	cat > /root/composer.json << "EOF"
{
    "require": {
	    "monolog/monolog": "2.0.*"
    }
} 

EOF

	# Mise a jour de composer avec -n comme argument qui ne demande pas d'interaction
	composer update -n
}


function install_bookstack()
{
	cd /var/www/

	# Telechargement de bookstack
	git clone https://github.com/BookStackApp/BookStack.git --branch release --single-branch

	mv /var/www/BookStack /var/www/bookstack

	cd /var/www/bookstack/

	composer install --no-dev -n	

	# .env fichier de config pour BookStack
	# Copier le fichier .env.example entrer l'email et le nom de la bdd dans le fichier .env
	cp /var/www/bookstack/.env.example /var/www/bookstack/.env

	# Remplacement de la configuration de la bdd
	sed -i "s/database_database/bookstack/" /var/www/bookstack/.env
	sed -i "s/database_username/bookstackuser/" /var/www/bookstack/.env
	sed -i "s/database_user_password/password/" /var/www/bookstack/.env

	# Changer l'URL
	sed -i "s;https://example.com;http://wiki.lyronn.local;" /var/www/bookstack/.env	

	# Generer la cle d'application 
	yes | php artisan key:generate

	# Gestion d'erreur
	if echo $?==0; then
		echo "Cle d'application générée"
	else
		echo "Erreur: cle d'application non générée"
		exit
	fi

	# Changer les droits pour /var/www/bookstack
	# Apporte une sécurité supplémentaire en cas d'attaque
	# Il faut éviter que tous les fichiers appartiennent à root
	chown -Rv lyronn:lyronn /var/www/bookstack

	# Changer les droits d'acces pour /var/www/bookstack/storage /var/www/bootsrap/cache et /var/www/public/uploads
	chown -Rv www-data:www-data /var/www/bookstack/storage
	chown -Rv www-data:www-data /var/www/bookstack/bootstrap/cache
	chown -Rv www-data:www-data /var/www/bookstack/public/uploads

	# Configurer le fichier root de nginx dans /etc/nginx/sites-available
	cat > /etc/nginx/sites-available/bookstack.conf << "EOF"
server {
	listen 80;
  	listen [::]:80;

	server_name wiki.lyronn.local;

  	root /var/www/bookstack/public;
	index index.php index.html;

	location / {
	    try_files $uri $uri/ /index.php?$query_string;
	}
   
	location ~ \.php$ {
	include snippets/fastcgi-php.conf;
       	 fastcgi_pass unix:/run/php/php7.4-fpm.sock;
       	}
}

EOF

	# Lien symbolique entre les sites-available et les sites-enabled
	ln -s /etc/nginx/sites-available/bookstack.conf /etc/nginx/sites-enabled/

	# Mise a jour de la base de donnee
	# Cette instruction doit être commentée dans le cadre d'une restauration de la bdd
	yes | php artisan migrate
	
}

function restore_db()
{
	# Restauration de la bdd
	mysql -u root bookstack < ~/bookstack.backup.sql

	# Restauration des fichiers
	tar -xvzf ~/bookstack-files-backup.tar.gz
}

clear

# Utile lorsqu'on utilise des snapshots qui ne sont pas l'heure
echo "Synchronisation de l'heure"
# ntpdate pool.ntp.org
timedatectl set-ntp on
systemctl restart systemd-timesyncd
systemctl status systemd-timesyncd --no-pager

echo "Mises à jour et installation de nginx"
nginx_install

sleep 10

echo "Installation de mariadb et my_sql_secure_installation"
mariadb_install

sleep 10

echo "Configuration de MariaDB"
configure_mariadb

echo "Installation de php"
php_install

sleep 10

echo "Redémarrer nginx"
systemctl restart nginx.service

sleep 10

echo "Installation de composer"
configure_composer

sleep 10

echo "Installation de BookStack"
install_bookstack

sleep 10

echo "Redémarrage de nginx"
systemctl restart nginx.service

echo "Redémarrage de php7.4-fpm"
systemctl restart php7.4-fpm

# echo "Restauration de la bdd"
# restore_db
