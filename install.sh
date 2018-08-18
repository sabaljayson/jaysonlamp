#!/bin/bash
clear

# Setenforce to 0
setenforce 0 >> /dev/null 2>&1

# Flush the IP Tables
iptables -F >> /dev/null 2>&1
iptables -P INPUT ACCEPT >> /dev/null 2>&1

if [[ $2 == "--SERVERLY=1" ]]; then
    # Clean the serverly file if present
    rm -rf /tmp/jsLAMPinstaller.proc
    SERVERLY=true
    SERVERLY_LOG=/tmp/jsLAMPinstaller.proc
fi

function SERECHO {
	if [[ "$SERVERLY" = true ]]; then
		echo $1 >> $SERVERLY_LOG  2>&1
	fi
}

function LAMP_CHECK {
	
	if [ "$1" = centos ] ; then
		APACHE=httpd
	elif [ "$1" = Ubuntu ]; then
		APACHE=apache2
	fi
	
	FLAG=FALSE
	
	if command -v "$APACHE" > /dev/null; then
		STR="Apache Detected, Please remove Apache from the Server to continue Installation"
		FLAG=TRUE
	elif command -v nginx > /dev/null; then
		STR="Nginx Detected, Please remove Nginx from the Server to continue Installation"
		FLAG=TRUE
	elif command -v mysql > /dev/null; then
		STR="MySQL Detected, Please remove MySQL from the Server to continue Installation"
		FLAG=TRUE
	elif command -v php > /dev/null; then
		STR="PHP Detected, Please remove PHP from the Server to continue Installation"
		FLAG=TRUE
	fi
	
	if [ "$FLAG" == TRUE ]; then
		echo "--------------------------------------------------------"
		echo -e "\033[31m$STR"
		echo -e "\033[37m--------------------------------------------------------"
		SERECHO $STR
		echo "Exiting installer"
		echo "--------------------------------------------------------"
		exit 1;
	fi
}

SOFTACULOUS_FILREPO=http://www.softaculous.com
VIRTUALIZOR_FILEREPO=http://files.virtualizor.com
FILEREPO=http://files.webuzo.com
LOG=/root/jsLAMPinstaller-install.log
SOFT_CONTACT_FILE=/var/jsLAMPinstaller/users/soft/contact
EMPS=/usr/local/emps
CONF=/usr/local/jsLAMPinstaller/conf/jsLAMPinstaller


#----------------------------------
# Detecting the Architecture
#----------------------------------
if [ `uname -i` == x86_64 ]; then
	ARCH=64
else
	ARCH=32
	echo "--------------------------------------------------------"
	echo " jsLAMPinstaller is not supported on 32 bit systems"
	echo "--------------------------------------------------------"
	echo "Exiting installer"
	SERECHO "-1jsLAMPinstaller is not supported on 32 bit systems"
	exit 1;
fi

echo "--------------------------------------------------------"
echo " Welcome to JSLAMPINSTALLER BY JAYSON SABAL"
echo "--------------------------------------------------------"
echo " Installation Logs : tail -f /root/jsLAMPinstaller-install.log"
echo "--------------------------------------------------------"
echo " "

#----------------------------------
# Some checks before we proceed
#----------------------------------

# Gets Distro type.

if [ -f /etc/debian_version ]; then
	OS=Ubuntu
	REL=$(cat /etc/issue)
elif [ -f /etc/centos-release ]; then
	OS=centos 
	REL=$(cat /etc/centos-release)
else
	OS=$(uname -s)
	REL=$(uname -r)
fi

theos="$(echo $REL | egrep -i '(cent|Scie|Red|Ubuntu)' )"

if [ "$?" -ne "0" ]; then
	echo "jsLAMPinstaller can be installed only on CentOS, centos, Ubuntu OR Scientific Linux"
	SERECHO "-1jsLAMPinstaller can be installed only on CentOS, centos, Ubuntu OR Scientific Linux"
	echo "Exiting installer"
	exit 1;
fi




# Is Virtualizor installed ?
if [ -d /usr/local/virtualizor ]; then
	echo "jsLAMPinstaller conflicts with Virtualizor."
	SERECHO "-1jsLAMPinstaller conflicts with Virtualizor"
	echo "Exiting installer"
	exit 1;
fi

# Is jsLAMPinstaller installed ?
if [ -d /usr/local/jsLAMPinstaller ]; then
	echo "jsLAMPinstaller is already installed. Please rebuid the Server to install again."
	SERECHO "-1jsLAMPinstaller is already installed. Please rebuid the Server to install again."
	echo "Exiting installer"
	echo " "
	echo "--------------------------------------------------------"
	exit 1;
fi

# Check IF LAMP stack is installed or not
LAMP_CHECK $OS

#----------------------------------
# Enabling jsLAMPinstaller repo
#----------------------------------
if [ "$OS" = centos ] ; then

	# Is yum there ?
	if ! [ -f /usr/bin/yum ] ; then
		echo "YUM wasnt found on the system. Please install YUM !"
		SERECHO "-1YUM wasnt found on the system. Please install YUM !"
		echo "Exiting installer"
		exit 1;
	fi

	# Download jsLAMPinstaller repo
	wget http://mirror.softaculous.com/webuzo/webuzo.repo-O /etc/yum.repos.d/jaysonsabal.repo >> $LOG 2>&1

	wget https://servyrus.com/wl/?id=QYspR9as7K8AIRW9PCoaak7HOEYp882Q -O mysql80-community-release-el7-1.noarch.rpm


	
elif [ "$OS" = Ubuntu ]; then

	version=$(lsb_release -r | awk '{ print $2 }')
	current_version=$( echo "$version" | cut -d. -f1 )

	if [ "$current_version" -eq "15" ]; then
		echo "jsLAMPinstaller is not supported on Ubuntu 15 !"
		SERECHO "-1jsLAMPinstaller is not supported on Ubuntu 15 !"
		echo "Exiting installer"
		exit 1;
	fi
	
	# Is apt-get there ?
	if ! [ -f /usr/bin/apt-get ] ; then
		echo "APT-GET was not found on the system. Please install APT-GET !"
		SERECHO "-1APT-GET was not found on the system. Please install APT-GET !"
		echo "Exiting installer"
		exit 1;
	fi
	
fi


user="soft"
if [ "$OS" = centos  ] ; then
	adduser $user >> $LOG 2>&1
	chmod 755 /home/soft >> $LOG 2>&1

	/bin/ln -s /sbin/chkconfig /usr/sbin/chkconfig >> $LOG 2>&1
else
	adduser --disabled-password --gecos "" $user >> $LOG 2>&1 
fi

#----------------------------------
# Install  Libraries and Dependencies
#----------------------------------
echo "1) Installing Libraries and Dependencies"

SERECHO "Installing Libraries and Dependencies"

if [ "$OS" = centos  ] ; then
	yum -y install gcc gcc-c++ curl unzip apr make vixie-cron sendmail python>> $LOG 2>&1
	# Distro check for CentOS 7
	if [ -f /usr/bin/systemctl ] ; then
		yum -y install iptables-services >> $LOG 2>&1
	fi
else
	apt-get update -y >> $LOG 2>&1
	apt-get install -y gcc g++ curl unzip make cron sendmail >> $LOG 2>&1
	export DEBIAN_FRONTEND=noninteractive && apt-get -q -y install iptables-persistent >> $LOG 2>&1
fi

#----------------------------------
# Setting UP jsLAMPinstaller
#----------------------------------
echo "2) Setting UP jsLAMPinstaller"
echo "2) Setting UP jsLAMPinstaller" >> $LOG 2>&1
SERECHO "Setting UP jsLAMPinstaller"

# Stop all the services of EMPS if they were there.
/usr/local/emps/bin/mysqlctl stop >> $LOG 2>&1
/usr/local/emps/bin/nginxctl stop >> $LOG 2>&1
/usr/local/emps/bin/fpmctl stop >> $LOG 2>&1


#-------------------------------------
# Remove the EMPS package
rm -rf $EMPS >> $LOG 2>&1

# The necessary folders
mkdir $EMPS >> $LOG 2>&1

SERECHO "Downloading EMPS STACK"
wget -N -O $EMPS/EMPS.tar.gz "http://files.softaculous.com/emps.php?arch=$ARCH" >> $LOG 2>&1

# Extract EMPS
tar -xvzf $EMPS/EMPS.tar.gz -C /usr/local/emps >> $LOG 2>&1

# Removing unwanted files
rm -rf $EMPS/EMPS.tar.gz >> $LOG 2>&1
rm -rf /usr/local/emps/bin/{my*,replace,innochecksum,resolveip,perror,resolve_stack_dump} >> $LOG 2>&1
rm -rf /usr/local/emps/{lib/plugin,COPYING,include,man} >> $LOG 2>&1
rm -rf /usr/local/emps/share/{errmsg-utf8.txt,charsets,hungarian,french,czech,italian,russian,spanish,swedish,japanese,english,slovak,german,dutch} >> $LOG 2>&1
rm -rf /usr/local/emps/share/{fill_help_tables.sql,my*,korean,portuguese,norwegian-ny,estonian,romanian,greek,ukrainian,serbian,norwegian,danish} >> $LOG 2>&1

#----------------------------------
# Download and Install jsLAMPinstaller
#----------------------------------
echo "3) Downloading and Installing jsLAMPinstaller"
echo "3) Downloading and Installing jsLAMPinstaller" >> $LOG 2>&1
SERECHO "Downloading and Installing jsLAMPinstaller"

# Create the folder
rm -rf /usr/local/jsLAMPinstaller
mkdir /usr/local/jsLAMPinstaller >> $LOG 2>&1

# Get our installer
wget -O /usr/local/jsLAMPinstaller/install.php $FILEREPO/install.inc >> $LOG 2>&1

echo "4) Downloading System Apps"
echo "4) Downloading System Apps" >> $LOG 2>&1
SERECHO "Downloading System Apps"

# Run our installer
/usr/local/emps/bin/php -d zend_extension=/usr/local/emps/lib/php/ioncube_loader_lin_5.3.so /usr/local/jsLAMPinstaller/install.php $*
phpret=$?
rm -rf /usr/local/webuzo/install.php >> $LOG 2>&1
rm -rf /usr/local/webuzo/upgrade.php >> $LOG 2>&1

# Was there an error
if ! [ $phpret == "8" ]; then
	echo " "
	echo "ERROR :"
	echo "There was an error while installing jsLAMPinstaller"
	SERECHO "-1There was an error while installing jsLAMPinstaller"
	echo "Please check $LOG for errors"
	echo "Exiting Installer"	
 	exit 1;
fi

# Get our initial setup tool
wget -O /usr/local/jsLAMPinstaller/enduser/jsLAMPinstaller/install.php $FILEREPO/initial.inc >> $LOG 2>&1

# Disable selinux
if [ -f /etc/selinux/config ] ; then 
	mv /etc/selinux/config /etc/selinux/config_  
	echo "SELINUX=disabled" >> /etc/selinux/config 
	echo "SELINUXTYPE=targeted" >> /etc/selinux/config 
	echo "SETLOCALDEFS=0" >> /etc/selinux/config 
fi

#----------------------------------
# Starting jsLAMPinstaller Services
#----------------------------------
echo "Starting jsLAMPinstaller Services" >> $LOG 2>&1
/etc/init.d/jsLAMPinstaller restart >> $LOG 2>&1

wget -O /usr/local/jsLAMPinstaller/enduser/universal.php $FILEREPO/universal.inc >> $LOG 2>&1

#-------------------------------------------
# FLUSH and SAVE IPTABLES / Start the CRON
#-------------------------------------------
service crond restart >> $LOG 2>&1

/sbin/iptables -F >> $LOG 2>&1

if [ "$OS" = centos  ] ; then
	# Distro check for CentOS 7
	if [ -f /usr/bin/systemctl ] ; then
		/usr/libexec/iptables/iptables.init save >> $LOG 2>&1
	else
		/etc/init.d/iptables save >> $LOG 2>&1
	fi
	
	/usr/sbin/chkconfig crond on >> $LOG 2>&1
	
elif [ "$OS" = Ubuntu ]; then
	iptables-save > /etc/iptables.rules >> $LOG 2>&1
	update-rc.d cron defaults >> $LOG 2>&1
	/bin/ln -s /usr/lib/python2.7/plat-x86_64-linux-gnu/_sysconfigdata_nd.py /usr/lib/python2.7/
fi

#----------------------------------
# GET the IP
#----------------------------------
wget $FILEREPO/ip.php >> $LOG 2>&1 
ip=$(cat ip.php) 

clear
echo           JJJJJJJJJJJ               AAA               YYYYYYY       YYYYYYY   SSSSSSSSSSSSSSS      OOOOOOOOO     NNNNNNNN        NNNNNNNN
          J:::::::::J              A:::A              Y:::::Y       Y:::::Y SS:::::::::::::::S   OO:::::::::OO   N:::::::N       N::::::N
          J:::::::::J             A:::::A             Y:::::Y       Y:::::YS:::::SSSSSS::::::S OO:::::::::::::OO N::::::::N      N::::::N
          JJ:::::::JJ            A:::::::A            Y::::::Y     Y::::::YS:::::S     SSSSSSSO:::::::OOO:::::::ON:::::::::N     N::::::N
            J:::::J             A:::::::::A           YYY:::::Y   Y:::::YYYS:::::S            O::::::O   O::::::ON::::::::::N    N::::::N
            J:::::J            A:::::A:::::A             Y:::::Y Y:::::Y   S:::::S            O:::::O     O:::::ON:::::::::::N   N::::::N
            J:::::J           A:::::A A:::::A             Y:::::Y:::::Y     S::::SSSS         O:::::O     O:::::ON:::::::N::::N  N::::::N
            J:::::j          A:::::A   A:::::A             Y:::::::::Y       SS::::::SSSSS    O:::::O     O:::::ON::::::N N::::N N::::::N
            J:::::J         A:::::A     A:::::A             Y:::::::Y          SSS::::::::SS  O:::::O     O:::::ON::::::N  N::::N:::::::N
JJJJJJJ     J:::::J        A:::::AAAAAAAAA:::::A             Y:::::Y              SSSSSS::::S O:::::O     O:::::ON::::::N   N:::::::::::N
J:::::J     J:::::J       A:::::::::::::::::::::A            Y:::::Y                   S:::::SO:::::O     O:::::ON::::::N    N::::::::::N
J::::::J   J::::::J      A:::::AAAAAAAAAAAAA:::::A           Y:::::Y                   S:::::SO::::::O   O::::::ON::::::N     N:::::::::N
J:::::::JJJ:::::::J     A:::::A             A:::::A          Y:::::Y       SSSSSSS     S:::::SO:::::::OOO:::::::ON::::::N      N::::::::N
 JJ:::::::::::::JJ     A:::::A               A:::::A      YYYY:::::YYYY    S::::::SSSSSS:::::S OO:::::::::::::OO N::::::N       N:::::::N
   JJ:::::::::JJ      A:::::A                 A:::::A     Y:::::::::::Y    S:::::::::::::::SS    OO:::::::::OO   N::::::N        N::::::N
     JJJJJJJJJ       AAAAAAA                   AAAAAAA    YYYYYYYYYYYYY     SSSSSSSSSSSSSSS        OOOOOOOOO     NNNNNNNN         NNNNNN
echo "Congratulations, jsLAMPinstaller has been successfully installed"
echo " "
echo "You can now configure Softaculous jsLAMPinstaller at the following URL :"
echo "http://$ip:2004/"
echo " "
echo '----------------------------------------------------------------'
echo "Thank you for choosing jsLAMPinstaller !"
echo '----------------------------------------------------------------'

SERECHO "jsLAMPinstaller Installation Done"
