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
	# après l'installation de cheat
	# umask 002
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
}

function configure_mariadb()
{
	mysql -e "CREATE DATABASE bookstack;"
	mysql -e 'GRANT ALL ON bookstack.* TO "bookstackuser"@"localhost" IDENTIFIED BY "password";'
	mysql -e "FLUSH PRIVILEGES;"

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
	# Les quotes permettent de protéger le EOF et d'insérer l'étoile
	cat > /root/composer.json << "EOF"
{
    "require": {
	    "monolog/monolog": "2.0.*"
    }
} 

EOF

	#mise a jour de composer avec -n comme argument qui ne demande pas d'interaction
	composer update -n
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
	sed -i "s/database_username/bookstackuser/" /var/www/bookstack/.env
	sed -i "s/database_user_password/password/" /var/www/bookstack/.env

	#changer l'URL
	sed -i "s;https://example.com;http://wiki.lyronn.local;" /var/www/bookstack/.env	

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

EOF

	#mise a jour de la base de donnee
	yes | php artisan migrate
	
}

function bookstack_rights()
{
	chown -Rv www-data:www-data /root/BookStack/storage
	chown -Rv www-data:www-data /root/BookStack/bootstrap/cache
	chown -Rv www-data:www-data /root/BookStack/public/uploads

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

sleep 15

echo "Installation de composer"
configure_composer

sleep 15

echo "Installation de BookStack"
install_bookstack

sleep 10

echo "Modification des droits des fichiers de configuration bookstack"
bookstack_rights

sleep 10

echo "Redémarrage de nginx"
systemctl restart nginx

