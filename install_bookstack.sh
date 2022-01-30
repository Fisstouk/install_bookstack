#!/bin/bash
#
#version:1.0
#
#auteur:lyronn

#affiche les commandes realisees
set -x

#arrete le script des qu'une erreur survient
set -e

function nginx_install()
{
	#modifie temporairement le umask
	umask 002
	#mise a jour et installation de nginx et git
	apt update -y
	apt install nginx -y
	apt install git -y

	#demarrer le service nginx et l'activer a chaque demarrage
	systemctl start nginx.service
	systemctl enable nginx.service
}

function mariadb_install()
{
	apt install mariadb-server -y
	systemctl start mysql.service
	systemctl enable mysql.service

	#installation de mysql_secure_installation
	#mot de passe pour root
	#mysql -e "UPDATE mysql.user SET Password = PASSWORD('CHANGEME') WHERE User = 'root'"
	#supprimer les utilisateurs anonymes
	#mysql -e "DROP USER ''@'localhost'"
	#supprime la bdd de demo
	#mysql -e "DROP DATABASE test"
	#reinitialiser les privileges
	#mysql -e "FLUSH PRIVILEGES"
}

function php_install()
{
	apt install php-fpm -y

	#demarrer php
	systemctl start php7.4-fpm.service
	systemctl enable php7.4-fpm.service

	#installation des extensions php suivantes
	#MBstring
	apt install php7.4-mbstring -y

	#Tokenizer
	apt install php-tokenizer -y

	#GD
	apt install php-gd -y

	#MySQL
	apt install php-mysql -y

	#SimpleXML et DOM
	apt install php-xml -y

}

function configure_mariadb()
{
	#connection en root a la bdd
	#mettre un espace apres -p demandera t'interargir avec mysql
	#mysql -u "root" "-paze!123"

	#cree la bdd nomme bookstack
	mysql -e "CREATE DATABASE bookstack;"

	#creation de l'utilisateur nimda avec son mdp en tant qu'admin
	mysql -e "CREATE USER 'nimda'@'localhost' IDENTIFIED BY 'aze\!123';"

	#creation de l'utilisateur lyronn en tant que viewer
	mysql -e "CREATE USER 'lyronn'@'localhost' IDENTIFIED BY 'aze\!123';"

	#creation de l'utilisateur guest en tant qu'invite
	mysql -e "CREATE USER 'guest'@'localhost' IDENTIFIED BY 'aze\!123';"

	#donne les droits admin a nimda
	mysql -e 'GRANT ALL ON bookstack.* TO "nimda"@"localhost" IDENTIFIED BY "aze\!123" WITH GRANT OPTION;'

	#enregistre et quitte la bdd
	mysql -e "FLUSH PRIVILEGES;"
}

function configure_composer()
{	
	#installatin de unzip
	apt install unzip -y

	#installation de composer
	php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"

	#verification du hash
	php -r "if (hash_file('sha384', 'composer-setup.php') === '906a84df04cea2aa72f40b5f787e49f22d4c2f19492ac310e8cba5b96ac8b64115ac402c8cd292b8a03482574915d1a8') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"

	php composer-setup.php

	php -r "unlink('composer-setup.php');"

	#deplace le fichier composer.phar dans /usr/local/bin/composer pour executer composer
	mv -v composer.phar /usr/local/bin/composer

	#installe php-curl pour mettre a jour composer
	apt install php7.4-curl -y

	#cree le fichier composer.json pour demarrer un projet
	echo '
	{
	    "require": {
	            "monolog/monolog": "2.0.*"
	    }
	}' >> /root/composer.json

	#mise a jour de composer avec -n comme argument qui ne demande pas d'interaction
	composer update -n
}

function bookstack_rights()
{
	groupadd bookstack
	
	chgrp -Rv bookstack /root/BookStack/storage

	chgrp -Rv bookstack /root/BookStack/bootstrap/cache

	chgrp -Rv bookstack /root/BookStack/public/uploads

	usermod -aG bookstack www-data
	usermod -aG bookstack root

	chmod 770 /root/BookStack/storage

	chmod 770 /root/BookStack/bootstrap/cache

	chmod 770 /root/BookStack/public/uploads

}

function install_bookstack()
{
	cd /var/www/

	#telechargement de bookstack
	git clone https://github.com/BookStackApp/BookStack.git --branch release --single-branch

	mv /var/www/BookStack /var/www/bookstack

	cd /var/www/bookstack/

	composer install --no-dev -n	

	#.env fichier de config pour BookStack
	#copier le fichier .env.example entrer l'email et le nom de la bdd dans le fichier .env
	cp /var/www/bookstack/.env.example /var/www/bookstack/.env

	#remplacement de la configuration de la bdd
	sed -i "s/database_database/bookstack/" /var/www/bookstack/.env
	sed -i "s/database_username/nimda/" /var/www/bookstack/.env
	sed -i "s/database_user_password/aze\!123/" /var/www/bookstack/.env

	#changer l'URL
	sed -i "s;https://example.com;http://lyronn-bookstack.com;" /var/www/bookstack/.env	

	#generer la cle d'application 
	yes | php artisan key:generate

	#changer les droits d'acces pour /var/www/bookstack
	chown -R www-data:www-data /var/www/bookstack
	chmod -R 755 /var/www/bookstack

	#gestion d'erreur
	if echo $?==0; then
		echo "Cle d'application générée"
	else
		echo "Erreur: cle d'application non générée"
		exit
	fi

	#configurer le fichier root de nginx dans /etc/nginx/sites-enabled/default
	echo '
server {
	listen 80;
  	listen [::]:80;

	server_name lyronn-bookstack.com;

  	root /var/www/bookstack/public;
	index index.php index.html;

	location / {
	    try_files $uri $uri/ /index.php?$query_string;
	}
   
	location ~ \.php$ {
	include snippets/fastcgi-php.conf;
       	 fastcgi_pass unix:/run/php/php7.4-fpm.sock;
       	}
}' >> /etc/nginx/sites-enabled/bookstack-config	

	#mise a jour de la base de donnee
	yes | php artisan migrate
	
}

function db_bookstack()
{
	#creation du compte nimda
	mysql -e '
	USE bookstack; 
	INSERT INTO users (id, name, email, password, created_at, updated_at, external_auth_id, slug) 
	VALUES ("3", "nimda", "nimda@admin.com", "azerty", CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, "NULL", "nimda");'

	#attribution du role a admin a nimda
	mysql -e 'USE bookstack; 
	INSERT INTO role_user (user_id, role_id) 
	VALUES ('3', '1');'

	#creation etagere
	mysql -e 'USE bookstack; 
	INSERT INTO bookshelves (name, slug, description, created_by, updated_by, created_at, updated_at, owned_by) 
	VALUES ("1.Administration Linux", "1.Administration Linux", "Cours Linux", 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1);'

	#mise a jour de bookstack
	cd /var/www/bookstack
	php artisan bookstack:regenerate-search
	php artisan bookstack:regenerate-permissions
}

clear

echo "Mises à jour et installation de nginx"
nginx_install

sleep 15

echo "Installation de mariadb et my_sql_secure_installation"
mariadb_install

sleep 15

echo "Installation de php"
php_install

sleep 15

echo "Redémarrer nginx"
systemctl restart nginx.service

sleep 5

echo "Ajout de l'utilisateur nimda"
configure_mariadb

sleep 15

echo "Installation de composer"
configure_composer

sleep 15

echo "Installation de BookStack"
install_bookstack

sleep 10

echo "Redémarrage de nginx"
systemctl restart nginx

#echo "Création du groupe bookstack"
#bookstack_rights

echo "Création du compte nimda, d'une étagère et d'un livre"
db_bookstack
