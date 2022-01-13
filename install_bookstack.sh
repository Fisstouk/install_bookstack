#!/bin/bash
#
#version:0.3
#
#auteur:lyronn

#affiche les commandes realisees
set -x

#arrete le script des qu'une erreur survient
set -e

function nginx_install()
{
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
	#installation des extensions php suivantes
	#OpenSSL

	#PDO pour lier php et mysql

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

	#demarrer php
	systemctl start php7.4-fpm.service
	systemctl enable php7.4-fpm.service
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
	#telechargement de bookstack
	git clone https://github.com/BookStackApp/BookStack.git --branch release --single-branch

	#installation de unzip pour installer BookStack
	apt install unzip -y

	cd /root/BookStack
	composer install --no-dev -n	
	cd /root/

	#.env fichier de config pour BookStack
	#copier le fichier .env.example entrer l'email et le nom de la bdd dans le fichier .env
	cp /root/BookStack/.env.example /root/Bookstack/.env

	#remplacement de la configuration de la bdd
	sed -i "s/database_database/bookstack/" /root/BookStack/.env
	sed -i "s/database_username/nimda/" /root/BookStack/.env
	sed -i "s/database_user_password/aze\!123/" /root/BookStack/.env

	#generer la cle d'application
	cd /root/BookStack
	yes | php artisan key:generate

	#gestion d'erreur
	if echo $?==0; then
		echo "Cle d'application générée"
	else
		echo "Erreur: cle d'application non générée"
		exit
	fi

	#configurer le fichier root de nginx dans /etc/nginx/sites-enabled/default
	sed -i "s;/var/www/example.com;/root/BookStack/public/;" /etc/nginx/sites-enabled/default

	#mise a jour de la base de donnee
	yes | php artisan migrate
	

}

clear

echo "Mises à jour et installation de nginx"
nginx_install

echo "Installation de mariadb et my_sql_secure_installation"
mariadb_install

echo "Installation de php"
php_install

echo "Redémarrer nginx"
systemctl restart nginx.service

echo "Ajout de l'utilisateur nimda"
configure_mariadb

echo "Installation de composer"
configure_composer
