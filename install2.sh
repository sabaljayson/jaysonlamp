#!/bin/bash
clear

setenforce 0 >> /dev/null 2>&1

# Flush the IP Tables
#iptables -F >> /dev/null 2>&1
#iptables -P INPUT ACCEPT >> /dev/null 2>&1

FILEREPO=http://files.virtualizor.com
LOG=/root/virtualizor.log

#----------------------------------
# Detecting the Architecture
#----------------------------------
if ([ `uname -i` == x86_64 ] || [ `uname -m` == x86_64 ]); then
	ARCH=64
else
	ARCH=32
fi

echo "-----------------------------------------------"
echo " Welcome to Jayson Sabal's LAMP Installer"
echo "-----------------------------------------------"
echo " "


#----------------------------------
# Some checks before we proceed
#----------------------------------

# Gets Distro type.
if [ -d /etc/pve ]; then
	OS=Proxmox
	REL=$(/usr/bin/pveversion)
elif [ -f /etc/debian_version ]; then	
	OS_ACTUAL=$(lsb_release -i | cut -f2)
	OS=Ubuntu
	REL=$(cat /etc/issue)
elif [ -f /etc/redhat-release ]; then
	OS=redhat 
	REL=$(cat /etc/redhat-release)
else
	OS=$(uname -s)
	REL=$(uname -r)
fi


if [ "$OS" = Ubuntu ] ; then

	# We dont need to check for Debian
	if [ "$OS_ACTUAL" = Ubuntu ] ; then
	
		VER=$(lsb_release -r | cut -f2)
		
		if  [ "$VER" != "12.04" -a "$VER" != "14.04" -a "$VER" != "16.04" ]; then
			echo "Softaculous Virtualizor only supports Ubuntu 12.04 LTS, Ubuntu 14.04 LTS and Ubuntu 16.04 LTS"
			echo "Exiting installer"
			exit 1;
		fi

		if ! [ -f /etc/default/grub ] ; then
			echo "Softaculous Virtualizor only supports GRUB 2 for Ubuntu based server"
			echo "Follow the Below guide to upgrade to grub2 :-"
			echo "https://help.ubuntu.com/community/Grub2/Upgrading"
			echo "Exiting installer"
			exit 1;
		fi
		
	fi
	
fi

theos="$(echo $REL | egrep -i '(cent|Scie|Red|Ubuntu|xen|Virtuozzo|pve-manager|Debian)' )"

if [ "$?" -ne "0" ]; then
	echo "Softaculous Virtualizor can be installed only on CentOS, Redhat, Scientific Linux, Ubuntu, XenServer, Virtuozzo and Proxmox"
	echo "Exiting installer"
	exit 1;
fi

# Is Webuzo installed ?
if [ -d /usr/local/webuzo ]; then
	echo "Server has webuzo installed. Virtualizor can not be installed."
	echo "Exiting installer"
	exit 1;
fi

#----------------------------------
# Is there an existing Virtualizor
#----------------------------------
if [ -d /usr/local/virtualizor ]; then

	echo "An existing installation of Virtualizor has been detected !"
	echo "If you continue to install Virtualizor, the existing installation"
	echo "and all its Data will be lost"
	echo -n "Do you want to continue installing ? [y/N]"
	
	read over_ride_install

	if ([ "$over_ride_install" == "N" ] || [ "$over_ride_install" == "n" ]); then	
		echo "Exiting Installer"
		exit;
	fi

fi

#----------------------------------
# Enabling Virtualizor repo
#----------------------------------
if [ "$OS" = redhat ] ; then

	# Is yum there ?
	if ! [ -f /usr/bin/yum ] ; then
		echo "YUM wasnt found on the system. Please install YUM !"
		echo "Exiting installer"
		exit 1;
	fi
	
	wget http://mirror.softaculous.com/virtualizor/virtualizor.repo -O /etc/yum.repos.d/virtualizor.repo >> $LOG 2>&1
	
	wget http://mirror.softaculous.com/virtualizor/extra/virtualizor-extra.repo -O /etc/yum.repos.d/virtualizor-extra.repo >> $LOG 2>&1

fi

#----------------------------------
# Install some LIBRARIES
#----------------------------------
echo "1) Installing Libraries and Dependencies"

echo "1) Installing Libraries and Dependencies" >> $LOG 2>&1

if [ "$OS" = redhat  ] ; then
	yum -y --enablerepo=updates update glibc libstdc++ >> $LOG 2>&1
	yum -y --enablerepo=base --skip-broken install e4fsprogs sendmail gcc gcc-c++ openssl unzip apr make vixie-cron crontabs fuse kpartx iputils >> $LOG 2>&1
	yum -y --enablerepo=base --skip-broken install postfix >> $LOG 2>&1
	yum -y --enablerepo=updates update e2fsprogs >> $LOG 2>&1
	yum -y install gcc g++ make automake autoconf curl-devel openssl-devel zlib-devel httpd-devel apr-devel apr-util-devel sqlite-devel wget >> $LOG 2>&1
	yum -y install ruby-rdoc ruby-devel >> $LOG 2>&1
	yum -y install wget >> $LOG 2>&1
	yum -y groupinstall "development tools" >> $LOG 2>&1
	yum install -y java-1.8.0-openjdk-devel >> $LOG 2>&1
	curl -o apache-maven-3.5.4-bin.tar.gz http://www-eu.apache.org/dist/maven/maven-3/3.5.4/binaries/apache-maven-3.5.4-bin.tar.gz >> $LOG 2>&1
	tar xvf apache-maven-3.5.4-bin.tar.gz >> $LOG 2>&1
	mv apache-maven-3.5.4  /usr/local/apache-maven >> $LOG 2>&1
	echo 'export M2_HOME=/usr/local/apache-maven' >> ~/.bashrc 
	echo 'export M2=$M2_HOME/bin' >> ~/.bashrc
	echo 'export PATH=$M2:$PATH' >> ~/.bashrc
	source ~/.bashrc
	
	gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 >> $LOG 2>&1
	curl -fsSL https://get.docker.com/ | sh >> $LOG 2>&1
	curl -sSL https://get.rvm.io | bash -s stable --ruby  >> $LOG 2>&1
	usermod -a -G rvm `whoami` >> $LOG 2>&1

elif [ "$OS" = Ubuntu  ] ; then
	
	if [ "$OS_ACTUAL" = Ubuntu  ] ; then
		apt-get update -y >> $LOG 2>&1
		apt-get install -y kpartx gcc openssl unzip sendmail make cron fuse e2fsprogs >> $LOG 2>&1
	else
		apt-get update -y >> $LOG 2>&1
		apt-get install -y kpartx gcc unzip make cron fuse e2fsprogs >> $LOG 2>&1
		apt-get install -y sendmail >> $LOG 2>&1
	fi
	
elif [ "$OS" = Proxmox  ] ; then
	apt-get update -y >> $LOG 2>&1
	
	if [ `echo $REL | grep -c "pve-manager/4" ` -gt 0 ] || [ `echo $REL | grep -c "pve-manager/5" ` -gt 0 ] ; then
        	apt-get install -y kpartx gcc openssl unzip make e2fsprogs gperf genisoimage flex bison pkg-config libpcre3-dev libreadline-dev libxml2-dev ocaml libselinux1-dev libsepol1-dev libfuse-dev libyajl-dev libmagic-dev >> $LOG 2>&1		
	else
        	apt-get install -y kpartx gcc openssl unzip make e2fsprogs gperf genisoimage flex bison pkg-config libpcre3-dev libreadline-dev libxml2-dev ocaml libselinux1-dev libsepol1-dev libyajl-dev libmagic-dev >> $LOG 2>&1
		wget http://download.proxmox.com/debian/dists/wheezy/pve-no-subscription/binary-amd64/libfuse-dev_2.9.2-4_amd64.deb >> $LOG 2>&1
		dpkg -i libfuse-dev_2.9.2-4_amd64.deb >> $LOG 2>&1
	fi
	
fi




#----------------------------------
# Install PHP, MySQL, Web Server
#----------------------------------
echo "2) Installing PHP, MySQL and Web Server"

# Stop all the services of EMPS if they were there.
/usr/local/emps/bin/mysqlctl stop >> $LOG 2>&1
/usr/local/emps/bin/nginxctl stop >> $LOG 2>&1
/usr/local/emps/bin/fpmctl stop >> $LOG 2>&1

# Remove the EMPS package
rm -rf /usr/local/emps/ >> $LOG 2>&1

# The necessary folders
mkdir /usr/local/emps >> $LOG 2>&1
mkdir /usr/local/virtualizor >> $LOG 2>&1

echo "1) Installing PHP, MySQL and Web Server" >> $LOG 2>&1
wget -N -O /usr/local/virtualizor/EMPS.tar.gz "http://files.softaculous.com/emps.php?arch=$ARCH" >> $LOG 2>&1

# Extract EMPS
tar -xvzf /usr/local/virtualizor/EMPS.tar.gz -C /usr/local/emps >> $LOG 2>&1
rm -rf /usr/local/virtualizor/EMPS.tar.gz >> $LOG 2>&1

#----------------------------------
# Download and Installing  Other Development Tools
#----------------------------------
echo "3) Downloading and Installing NodeJS"
echo "3) Downloading and Installing NodeJS" >> $LOG 2>&1

# Get our installer
curl --silent --location https://rpm.nodesource.com/setup_10.x | sudo bash - >> $LOG 2>&1
sudo yum -y install nodejs >> $LOG 2>&1

#echo "copying install file"
#mv install.inc /usr/local/virtualizor/install.php

sudo curl -L https://github.com/docker/compose/releases/download/1.22.0/docker-compose-$(uname -s)-$(uname -m) -o /usr//bin/docker-compose
sudo chmod +x /usr/bin/docker-compose >> $LOG 2>&1

sed -i 's/enforcing/disabled/g' /etc/selinux/config /etc/ >> $LOG 2>&1

adduser jaysonsabal >> $LOG 2>&1
sudo usermod -aG docker jaysonsabal >> $LOG 2>&1
sudo usermod -aG wheel jaysonsabal >> $LOG 2>&1
 
#----------------------------------
# Starting LAMP Services
#----------------------------------
echo "Starting LAMP Services" >> $LOG 2>&1

systemctl start httpd >> $LOG 2>&1
systemctl enable httpd >> $LOG 2>&1
systemctl start mysqld >> $LOG 2>&1
systemctl enable mysqld >> $LOG 2>&1

curl -o lando.rpm http://installer.kalabox.io/lando-latest-dev.rpm >> $LOG 2>&1
yum install -y lando-latest-dev.rpm  >> $LOG 2>&1

echo " "
echo "-------------------------------------"
echo " LAMP Installation Completed "
echo "-------------------------------------"
echo "Congratulations, Jayson's Installer for LAMP  has been successfully installed"

echo "Thank you for Using Jayson's Installer!"
