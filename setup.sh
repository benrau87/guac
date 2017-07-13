#!/bin/bash
####################################################################################################################
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit 1
fi
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
gitdir=$PWD

##Logging setup
logfile=/var/log/guac_install.log
mkfifo ${logfile}.pipe
tee < ${logfile}.pipe $logfile &
exec &> ${logfile}.pipe
rm ${logfile}.pipe

##Functions
function print_status ()
{
    echo -e "\x1B[01;34m[*]\x1B[0m $1"
}

function print_good ()
{
    echo -e "\x1B[01;32m[*]\x1B[0m $1"
}

function print_error ()
{
    echo -e "\x1B[01;31m[*]\x1B[0m $1"
}

function print_notification ()
{
	echo -e "\x1B[01;33m[*]\x1B[0m $1"
}

function error_check
{

if [ $? -eq 0 ]; then
	print_good "$1 successfully."
else
	print_error "$1 failed. Please check $logfile for more details."
exit 1
fi

}

function install_packages()
{

apt-get update &>> $logfile && apt-get install -y --allow-unauthenticated ${@} &>> $logfile
error_check 'Package installation completed'

}

function dir_check()
{

if [ ! -d $1 ]; then
	print_notification "$1 does not exist. Creating.."
	mkdir -p $1
else
	print_notification "$1 already exists. (No problem, We'll use it anyhow)"
fi

}
########################################
##BEGIN MAIN SCRIPT##
#Pre checks: These are a couple of basic sanity checks the script does before proceeding.

echo -e "${YELLOW}Please type in a MySQL password, this will be used for the guac database.${NC}"
read guac_mysql_pass

read -p "Do you already have a MySQL  service running? y/n" -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]
then
echo
echo -e "${YELLOW}Please type in the root user's password now${NC}"
read root_pass
else
echo
echo -e "${YELLOW}Please type in a root password now${NC}"
read new_root_pass
fi
debconf-set-selections <<< "mysql-server mysql-server/$new_root_pass password root" 

print_notification Updating stuff, hold on.
install_packages build-essential libcairo2-dev libjpeg-turbo8-dev libpng12-dev libossp-uuid-dev libavcodec-dev libavutil-dev libswscale-dev libfreerdp-dev libpango1.0-dev libssh2-1-dev libtelnet-dev libvncserver-dev libpulse-dev libssl-dev libvorbis-dev libwebp-dev mysql-server mysql-client mysql-common mysql-utilities tomcat8 freerdp ghostscript jq wget curl

SERVER=$(curl -s 'https://www.apache.org/dyn/closer.cgi?as_json=1' | jq --raw-output '.preferred|rtrimstr("/")')

echo "" >> /etc/default/tomcat8
echo "# GUACAMOLE EVN VARIABLE" >> /etc/default/tomcat8
echo "GUACAMOLE_HOME=/etc/guacamole" >> /etc/default/tomcat8
wget $SERVER/incubator/guacamole/0.9.12-incubating/source/guacamole-server-0.9.12-incubating.tar.gz
error_check server downloaded
wget $SERVER/incubator/guacamole/0.9.12-incubating/binary/guacamole-0.9.12-incubating.war
error_check war downloaded
wget $SERVER/incubator/guacamole/0.9.12-incubating/binary/guacamole-auth-jdbc-0.9.12-incubating.tar.gz
error_check auth downloaded
wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.41.tar.gz
error_check connector downloaded

tar -xzf guacamole-server-0.9.12-incubating.tar.gz
tar -xzf guacamole-auth-jdbc-0.9.12-incubating.tar.gz
tar -xzf mysql-connector-java-5.1.41.tar.gz

dir_check /etc/guacamole
dir_check /etc/guacamole/lib
dir_check /etc/guacamole/extensions

cd guacamole-server-0.9.12-incubating
./configure --with-init-dir=/etc/init.d
make
make install
ldconfig
systemctl enable guacd
cd ..

mv guacamole-0.9.12-incubating.war /etc/guacamole/guacamole.war
ln -s /etc/guacamole/guacamole.war /var/lib/tomcat8/webapps/
ln -s /usr/local/lib/freerdp/* /usr/lib/x86_64-linux-gnu/freerdp/.
cp mysql-connector-java-5.1.41/mysql-connector-java-5.1.41-bin.jar /etc/guacamole/lib/
cp guacamole-auth-jdbc-0.9.12-incubating/mysql/guacamole-auth-jdbc-mysql-0.9.12-incubating.jar /etc/guacamole/extensions/

echo "mysql-hostname: localhost" >> /etc/guacamole/guacamole.properties
echo "mysql-port: 3306" >> /etc/guacamole/guacamole.properties
echo "mysql-database: guacamole_db" >> /etc/guacamole/guacamole.properties
echo "mysql-username: guacamole_user" >> /etc/guacamole/guacamole.properties

echo "mysql-password: $guac_mysql_pass" >> /etc/guacamole/guacamole.properties
rm -rf /usr/share/tomcat8/.guacamole
ln -s /etc/guacamole /usr/share/tomcat8/.guacamole

# Restart Tomcat Service
service tomcat8 restart

if [ -z "$new_root_pass" ]
then
mysql -u root -p$root_pass
create database guacamole_db;
create user 'guacamole_user'@'localhost' identified by '$guac_mysql_pass';
GRANT SELECT,INSERT,UPDATE,DELETE ON guacamole_db.* TO 'guacamole_user'@'localhost';
flush privileges;
quit
cat guacamole-auth-jdbc-0.9.12-incubating/mysql/schema/*.sql | mysql -u root -p$root_pass guacamole_db
else
mysql -u root -p$new_root_pass
create database guacamole_db;
create user 'guacamole_user'@'localhost' identified by '$guac_mysql_pass';
GRANT SELECT,INSERT,UPDATE,DELETE ON guacamole_db.* TO 'guacamole_user'@'localhost';
flush privileges;
quit
cat guacamole-auth-jdbc-0.9.12-incubating/mysql/schema/*.sql | mysql -u root -p$new_root_pass guacamole_db
fi

# Cleanup Downloads
rm -rf guacamole-*
rm -rf mysql-connector-java-5.1.41*


echo -e "${YELLOW}Finished installation user is guacadmin password guacadmin.${NC}"
