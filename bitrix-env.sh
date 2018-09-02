#!/bin/bash

# variables
LOGS_FILE=$(mktemp /tmp/bitrix-env-XXXXX.log)
RELEASE_FILE=/etc/redhat-release
OS=$(awk '{print $1}' $RELEASE_FILE)
MYSQL_CNF=$HOME/.my.cnf
DEFAULT_SITE=/home/bitrix/www
POOL=0
[[ -z $SILENT ]] && SILENT=0
[[ -z $TEST_REPOSITORY ]] && TEST_REPOSITORY=0

BX_NAME=$(basename $0 | sed -e "s/\.sh$//")
if [[ $BX_NAME == "bitrix-env-crm" || $BX_NAME == "bitrix-env-crm-beta" ]]; then
    BX_PACKAGE="bitrix-env-crm"
    BX_TYPE=crm
else
    BX_PACKAGE="bitrix-env"
    BX_TYPE=general
fi

if [[ $(echo "$BX_NAME" | grep -c beta) -gt 0 ]]; then
    TEST_REPOSITORY=1
fi

# common subs
print(){
    msg=$1
    notice=${2:-0}
    [[ ( $SILENT -eq 0 ) && ( $notice -eq 1 ) ]] && echo -e "${msg}"
    [[ ( $SILENT -eq 0 ) && ( $notice -eq 2 ) ]] && echo -e "\e[1;31m${msg}\e[0m"
    echo "$(date +"%FT%H:%M:%S"): $$ : $msg" >> $LOGS_FILE
}

print_e(){
    msg_e=$1
    print "$msg_e" 2
    print "Installation logfile - $LOGS_FILE" 1
    exit 1
}

help_message(){
    echo <<EOF
    Usage: $0 [-s] [-t] [-p [-H hostname]] [-M mysql_root_password]
         -s - Silent or quiet mode. Don't ask any questions.
         -p - Create pool after installation of $BX_PACKAGE.
         -H - Hostname for for pool creation procedure.
         -M - Mysql password for root user
         -t - Use alfa/testing version of Bitrix Environment repository
    Example:
         * install $BX_PACKAGE and configure pool 
         $0 -s -p -H master1
         * install $BX_PACKAGE, configure pool and set mysql password
         $0 -s -p -H master1 -M 'password'
EOF
}

disable_selinux(){
    sestatus_cmd=$(which sestatus 2>/dev/null)
    [[ -z $sestatus_cmd ]] && return 0

    sestatus=$($sestatus_cmd | awk -F':' '/SELinux status:/{print $2}' | sed -e "s/\s\+//g")
    seconfigs="/etc/selinux/config /etc/sysconfig/selinux"
    if [[ $sestatus != "disabled" ]]; then
        print "You must disable SElinux before installing the Bitrix Environment." 1
        print "You need to reboot the server to disable SELinux"
        read -r -p "Do you want disable SELinux?(Y|n)" DISABLE
        [[ -z $DISABLE ]] && DISABLE=y
        [[ $(echo $DISABLE | grep -wci "y") -eq 0 ]] && print_e "Exit."
        for seconfig in $seconfigs; do
            [[ -f $seconfig ]] && \
                sed -i "s/SELINUX=\(enforcing\|permissive\)/SELINUX=disabled/" $seconfig && \
                print "Change SELinux state to disabled in $seconfig" 1
        done
        print "Please reboot the system! (cmd: reboot)" 1
        exit
    fi
}

# EPEL
configure_epel(){

    # testing rpm package
    EPEL=$(rpm -qa | grep -c 'epel-release')
    if [[ $EPEL -gt 0 ]]; then
        print "EPEL repository is already configured on the server." 1
        return 0
    fi
 
    # links
    print "Getting configuration EPEL repository. Please wait." 1
    if [[ $VER -eq 6 ]]; then
        LINK="https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm"
        GPGK="https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-6"
    else
        LINK="https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
        GPGK="https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-7"
    fi

    # configure repository
    rpm --import "$GPGK" >>$LOGS_FILE 2>&1 || \
        print_e "An error occurred during importing the EPEL GPG key: $GPGK"
    rpm -Uvh "$LINK" >>$LOGS_FILE 2>&1 || \
        print_e "An error occurred during installation the EPEL rpm-package: $LINK"

    # exclude ansible1.9
    echo "exclude=ansible1.9" >> /etc/yum.conf 
    
    # install packages
    yum clean all >/dev/null 2>&1 
    yum install -y yum-fastestmirror >/dev/null 2>&1

    print "Configuration EPEL repository is completed." 1
}

pre_php(){

    print "Enable remi repository"
    sed -i -e '/\[remi\]/,/^\[/s/enabled=0/enabled=1/' /etc/yum.repos.d/remi.repo

    print "Disable php56 repository"
    sed -i -e '/\[remi-php56\]/,/^\[/s/enabled=1/enabled=0/' /etc/yum.repos.d/remi.repo

    print "Disable php70 repository"
    sed -i -e '/\[remi-php70\]/,/^\[/s/enabled=1/enabled=0/' /etc/yum.repos.d/remi-php70.repo

    print "Enable php71 repository"
    sed -i -e '/\[remi-php71\]/,/^\[/s/enabled=0/enabled=1/' /etc/yum.repos.d/remi-php71.repo


    is_xhprof=$(rpm -qa | grep -c php-pecl-xhprof)
    if [[ $is_xhprof -gt 0 ]]; then
        yum -y remove php-pecl-xhprof
    fi
}

# REMI; php and mysql packages
configure_remi(){
    # testing rpm package
    EPEL=$(rpm -qa | grep -c 'remi-release')
    if [[ $EPEL -gt 0 ]]; then
        print "REMI repository is already configured on the server." 1
        return 0
    fi
 
    # links
    print "Getting configuration REMI repository. Please wait." 1
    GPGK="http://rpms.famillecollet.com/RPM-GPG-KEY-remi"
    if [[ $VER -eq 6 ]]; then
        LINK="http://rpms.famillecollet.com/enterprise/remi-release-6.rpm"
    else
        LINK="http://rpms.famillecollet.com/enterprise/remi-release-7.rpm"
    fi

    # configure repository
    rpm --import "$GPGK" >>$LOGS_FILE 2>&1 || \
        print_e "An error occurred during importing the REMI GPG key: $GPGK"
    rpm -Uvh "$LINK" >>$LOGS_FILE 2>&1 || \
        print_e "An error occurred during installation the REMI rpm-package: $LINK"
    
    
    # configure php 5.6
}


configure_mariadb(){
    # testing rpm package
    REPOTEST=$(yum repolist | grep -c 'mariadb')
    if [[ $REPOTEST -gt 0 ]]; then
        print "MariaDB repository is already configured on the server." 1
        return 0
    fi

    if [[ $IS_CENTOS7 -gt 0 ]]; then
        tee /etc/yum.repos.d/mariadb.repo << EOF
# MariaDB 5.5 CentOS repository list - created 2016-07-14 08:15 UTC
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/5.5/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF
        print "Configuration MariaDB repository is completed." 1
    else
        print "Configuration MariaDB repository is skipped." 1
    fi
}

configure_percona(){
    # testing rpm package
    REPOTEST=$(rpm -qa | grep -c 'percona-release')
    if [[ $REPOTEST -gt 0 ]]; then
        print "Percona repository is already configured on the server." 1
        return 0
    fi

    # links
    GPGK="http://www.percona.com/downloads/RPM-GPG-KEY-percona"
    LINK="http://www.percona.com/downloads/percona-release/redhat/0.1-4/percona-release-0.1-4.noarch.rpm"

    # configure repository
    rpm --import "$GPGK" >>$LOGS_FILE 2>&1 || \
        print_e "An error occurred during importing the Percona GPG key: $GPGK"
    rpm -Uvh "$LINK" >>$LOGS_FILE 2>&1 || \
        print_e "An error occurred during installation the Percona rpm-package: $LINK"

    print "Configuration Percona repository is completed." 1

}

configure_nodejs(){
    curl --silent --location https://rpm.nodesource.com/setup_8.x | bash - >>$LOGS_FILE 2>&1

    if [[ $IS_CENTOS73 -gt 0 ]]; then
        rpm -ivh \
            https://kojipkgs.fedoraproject.org//packages/http-parser/2.7.1/3.el7/x86_64/http-parser-2.7.1-3.el7.x86_64.rpm \
            >>$LOGS_FILE 2>&1
    fi
}

prepare_percona_install(){
    # test installed package
    INSTALLED_PACKAGES=$(rpm -qa)
    if [[ $(echo "$INSTALLED_PACKAGES" | grep -c "mariadb") -gt 0 ]]; then
        MARIADB_PACKAGES=$(echo "$INSTALLED_PACKAGES" | grep "mariadb")
        if [[ $(echo "$MARIADB_PACKAGES" | grep -vc "mariadb-libs") -gt 0 ]]; then
            print \
                "Found installed MariaDB server. Skip removing mariadb-libs."
        else
            yum -y remove mariadb-libs >/dev/null 2>&1
            print "Remove mariadb-libs package"
        fi
    fi
    
    if [[ $(echo "$INSTALLED_PACKAGES" | grep -c "mysql") -gt 0 ]]; then
        MYSQL_PACKAGES=$(echo "$INSTALLED_PACKAGES" | grep "mysql-libs")
        if [[ $(echo "$MYSQL_PACKAGES" | grep -vc "mysql-libs") -gt 0 ]]; then
            print \
                "Found installed MySQL server. Skip removing mysql-libs."
        else
            yum -y remove mysql-libs >/dev/null 2>&1
            print "Remove mysql-libs package"
        fi
    fi

}


configure_exclude(){
	if [[ $(grep -c "exclude" /etc/yum.conf) -gt 0 ]]; then
		sed -i \
			's/^exclude=.\+/exclude=ansible1.9,mysql,mariadb,mariadb-*,Percona-XtraDB-*,Percona-*-55,Percona-*-56,Percona-*-51,Percona-*-50/' \
			/etc/yum.conf
	else
		echo 'exclude=ansible1.9,mysql,mariadb,mariadb-*,Percona-XtraDB-*,Percona-*-55,Percona-*-56,Percona-*-51,Percona-*-50' >> /etc/yum.conf
	fi

}

# Bitrix; bitrix-env, bx-nginx
configure_bitrix(){
    # testing bitrix repository
    EPEL=$(yum repolist enabled | grep ^bitrix -c)
    if [[ $EPEL -gt 0 ]]; then
        print "Bitrix repository is already configured on the server." 1
        return 0
    fi

    # configure testing repository
    REPO=yum
    REPONAME=bitrix
    [[ $TEST_REPOSITORY -eq 1  ]] && \
        REPO=yum-beta && REPONAME=bitrix-beta
    [[ $TEST_REPOSITORY -eq 2 ]] && REPO=yum-testing
 
    # get GPG key
    print "Getting configuration Bitrix repository. Please wait." 1
    GPGK="http://repos.1c-bitrix.ru/yum/RPM-GPG-KEY-BitrixEnv"
    rpm --import "$GPGK" >>$LOGS_FILE 2>&1 || \
        print_e "An error occurred during importing the Bitrix GPG key: $GPGK"

    # create yum config file
    REPOF=/etc/yum.repos.d/bitrix.repo
    echo "[$REPONAME]" > $REPOF
    echo "name=\$OS \$releasever - \$basearch" >> $REPOF
    echo "failovermethod=priority" >> $REPOF
    echo "baseurl=http://repos.1c-bitrix.ru/$REPO/el/$VER/\$basearch" >> $REPOF
    echo "enabled=1" >> $REPOF
    echo "gpgcheck=1" >> $REPOF
    echo "gpgkey=$GPGK" >> $REPOF

    print "Configuration Bitrix repository is completed." 1
}

yum_update(){
	print "Update system. Please wait." 1
	yum -y update >>$LOGS_FILE 2>&1 || \
        print_e "An error occurred during the update the system."
}
ask_for_password(){
    MYSQL_ROOTPW=
    limit=5
    until [[ -n "$MYSQL_ROOTPW" ]]; do
        password_check=

        if [[ $limit -eq 0 ]]; then
            print "Have exhausted maximum number of retries for password set. Exit."
            return 1
        fi
        limit=$(( $limit - 1 ))

        read -s -r -p "Enter root password: " MYSQL_ROOTPW
        echo
        read -s -r -p "Re-enter root password: " password_check

        if [[ ( -n $MYSQL_ROOTPW ) && ( "$MYSQL_ROOTPW" = "$password_check" ) ]]; then
            :
        else
            [[ "$MYSQL_ROOTPW" != "$password_check" ]] && \
                print "Sorry, passwords do not match! Please try again."
            
            [[ -z "$MYSQL_ROOTPW" ]] && \
                print "Sorry, password can't be empty."
            MYSQL_ROOTPW=
        fi
    done
}

update_mysql_rootpw(){
    # update root password
    esc_pass=$(basic_single_escape "$MYSQL_ROOTPW")
    if [[ $MYSQL_MID_VERSION -gt 5 ]]; then
        my_query "ALTER USER 'root'@'localhost' IDENTIFIED BY '$esc_pass';" \
            "$mysql_update_config"
        my_query_rtn=$?
    else
        my_query \
            "UPDATE mysql.user SET Password=PASSWORD('$esc_pass') WHERE User='root'; FLUSH PRIVILEGES;" \
            "$mysql_update_config"
        my_query_rtn=$?
    fi

    if [[ $my_query_rtn -eq 0 ]]; then
        log_to_file "MySQL password update successfully"
        print "MySQL password update successfully" 1
        rm -f $mysql_update_config
    else
        log_to_file "MySQL password update failed"
        rm -f $mysql_update_config
        return 1
    fi

    # update client config
    my_config
    log_to_file "Update client config=$MYSQL_CNF"
    print "Update client config=$MYSQL_CNF" 1
}

configure_mysql_passwords(){
    [[ -z $MYSQL_VERSION  ]] && \
        get_mysql_package

    # start mysql
    my_start

    log_to_file \
        "Start update root password for MySQL Version=$MYSQL_VERSION($MYSQL_MID_VERSION)"

    ASK_USER_FOR_PASSWORD=0
    if [[ ! -f $MYSQL_CNF  ]]; then
        log_to_file "Not found default client config=$MYSQL_CNF"
        if [[ $MYSQL_MID_VERSION -eq 7 ]]; then
            MYSQL_LOG_FILE=/var/log/mysqld.log
            MYSQL_ROOTPW=$(grep 'temporary password' $MYSQL_LOG_FILE | awk '{print $NF}')
            MYSQL_ROOTPW_TYPE=temporary
        else
            MYSQL_ROOTPW=
            MYSQL_ROOTPW_TYPE=empty
        fi

        # test root has empty password
        local my_temp=$MYSQL_CNF.temp
        my_config "$my_temp"
        my_query "status;" "$my_temp"
        my_query_rtn=$?
        if [[ $my_query_rtn -gt 0 ]] ; then
            log_to_file "Found $MYSQL_ROOTPW_TYPE password; but it does not work"
            ASK_USER_FOR_PASSWORD=1
            mysql_update_config=
        else
            ASK_USER_FOR_PASSWORD=2
            mysql_update_config=$my_temp
        fi

    else
        MYSQL_ROOTPW_TYPE=saved
        log_to_file "Found default client config=$MYSQL_CNF"
        my_query "status;"
        my_query_rtn=$?
        if [[ $my_query_rtn -gt 0  ]] ; then
            log_to_file "Found $MYSQL_ROOTPW_TYPE password; but it does not work"
            ASK_USER_FOR_PASSWORD=1
            mysql_update_config=
        else
            test_empty_password=$(cat $MYSQL_CNF | grep password | \
                awk -F'=' '{print $2}' | sed -e "s/^\s\+//;s/\s\+$//" )
            if [[ ( -z $test_empty_password ) || \
                 ( $test_empty_password == '""' ) || \
                 ( $test_empty_password == "''" ) ]]; then
                ASK_USER_FOR_PASSWORD=2
                cp -f $MYSQL_CNF $MYSQL_CNF.temp
                mysql_update_config=$MYSQL_CNF.temp
            fi
        fi
    fi

    if [[ $ASK_USER_FOR_PASSWORD -eq 1 ]]; then
        log_to_file "Found $MYSQL_ROOTPW_TYPE root password; but it is does not work!"
        if [[ $SILENT -eq 0 ]]; then
            print "Found $MYSQL_ROOTPW_TYPE root password; but it is does not work!" 2
            read -r -p "Do you want update $MYSQL_CNF client config?(Y|n): " \
                user_answer
            [[ $( echo "$user_answer" | grep -wci "\(No\|n\)"  ) -gt 0  ]] && return 1

            # update client config
            ask_for_password
            [[ $? -gt 0 ]] && return 2
        else
            if [[ -n "$MYPASSWORD" ]]; then
                MYSQL_ROOTPW="${MYPASSWORD}"
            else
                log_to_file "User choose silent mode. Cannot set correct mysql password"
                return 1
            fi
        fi
        my_config
        print "Update client config=$MYSQL_CNF" 1

    elif [[ $ASK_USER_FOR_PASSWORD -eq 2 ]]; then
        log_to_file "Found $MYSQL_ROOTPW_TYPE root password; but you need to change it!"
        print "Found $MYSQL_ROOTPW_TYPE root password; but you need to change it!" 2

        if [[ $SILENT -eq 0 ]]; then

            read -r -p "Do you want change a password for root user in MySQL service?(Y|n): " \
                user_answer
            [[ $( echo "$user_answer" | grep -wci "\(No\|n\)" ) -gt 0 ]] && return 1

            # update root password and create client config
            ask_for_password 
            [[ $? -gt 0 ]] && return 2
        else
            if [[ -n "$MYPASSWORD" ]]; then
                MYSQL_ROOTPW="${MYPASSWORD}"
            else
                MYSQL_ROOTPW="$(randpw)"
            fi
        fi
        update_mysql_rootpw
    else
        log_to_file "Test $MYSQL_ROOTPW_TYPE root password - pass"
        if [[ -n "${MYPASSWORD}" ]]; then
            MYSQL_ROOTPW="${MYPASSWORD}"
            update_mysql_rootpw
        else
            if [[  ( $SILENT -eq 0 ) && ( $MYSQL_MID_VERSION -eq 7 ) ]]; then
                print "Root account created during the MySQL installation procedure." 1
                print "You can find root password at $HOME/.my.cnf client config file." 2
            fi
        fi
    fi
    # configure additinal options
    my_additional_security
    log_to_file "Main configuration of mysql security is complete"
    print "Main configuration of mysql security is complete" 1

}

# testing effective UID
[[ $EUID -ne 0 ]] && \
    print_e "This script must be run as root or it will fail" 

# testing OS name
[[ $OS != "CentOS" ]] && \
    print_e "This script is designed for use in OS CentOS Linux; Current OS=$OS"

# get cmd options
while getopts ":H:M:spt" opt; do
    case $opt in
        "H") HOSTIDENT="${OPTARG}" ;;
        "M") MYPASSWORD="${OPTARG}" ;;
        "s") SILENT=1 ;;
        "p") POOL=1 ;;
        "t") TEST_REPOSITORY=2 ;;
    esac
done

# Notification
if [[ $SILENT -eq 0 ]]; then
    print "====================================================================" 2
    print "Bitrix Environment for Linux installation script." 2
    print "Yes will be assumed to answers, and will be defaulted." 2
    print "'n' or 'no' will result in a No answer, anything else will be a yes." 2
    print "This script MUST be run as root or it will fail" 2
    print "====================================================================" 2

    ASK_USER=1
else
    ASK_USER=0
fi

# testing Centos vesrion
IS_CENTOS7=$(grep -c 'CentOS Linux release' $RELEASE_FILE)
IS_CENTOS73=$(grep -c "CentOS Linux release 7.3" $RELEASE_FILE)
IS_X86_64=$(uname -p | grep -wc 'x86_64')
if [[ $IS_CENTOS7 -gt 0 ]]; then
    VER=$(awk '{print $4}' $RELEASE_FILE | awk -F'.' '{print $1}')
else
    VER=$(awk '{print $3}' $RELEASE_FILE | awk -F'.' '{print $1}')
fi
if [[ $BX_PACKAGE == "bitrix-env-crm" ]]; then
    [[ ( $VER -eq 7 ) ]] || \
        print_e "The script does not support the Centos ${VER}."
else
    [[ ( $VER -eq 7 ) || ( $VER -eq 6 ) ]] || \
        print_e "The script does not support the Centos ${VER}."
fi


disable_selinux

# update all packages
yum_update

# configure repositories
configure_epel
configure_remi
pre_php
configure_percona
configure_nodejs
configure_bitrix

# prepare for percona
prepare_percona_install

# exclude settings
configure_exclude

# update all packages (EPEL and REMI packages)
yum_update

print "Install php packages. Please wait." 1
yum -y install php php-mysql \
    php-pecl-apcu php-pecl-zendopcache >>$LOGS_FILE 2>&1 || \
    print_e "An error occurred during installation of php-packages"

if [[ $BX_PACKAGE == "bitrix-env-crm" ]]; then
    yum -y install bx-push-server  >>$LOGS_FILE 2>&1 || \
        print_e "An error occurred during installation of bx-push-server"
fi

print "Install $BX_PACKAGE package. Please wait." 1
yum -y install $BX_PACKAGE >>$LOGS_FILE 2>&1 || \
    print_e "An error occurred during installation of $BX_PACKAGE package"

# upload bitrix proc
. /opt/webdir/bin/bitrix_utils.sh || exit 1

configure_mysql_passwords

update_crypto_key

# default configuration for host
if [[ $BX_PACKAGE == "bitrix-env-crm" ]]; then
    # configure pool
    generate_ansible_inventory $ASK_USER "$BX_TYPE" "$HOSTIDENT"  || \
        print_e "Cannot create management pool; Please see $LOGS_FILE"
    print "Management pool configuration is completed" 1

    # update push
    generate_push
else
    if [[ $POOL -gt 0 ]]; then
        generate_ansible_inventory $ASK_USER "$BX_TYPE" "$HOSTIDENT" || \
            print_e "Cannot create management pool; Please see $LOGS_FILE"
        print "Management pool configuration is completed" 1
    else
        configure_iptables >/dev/null 2>&1 || \
            print_e "Cannot configure firewall on the server. PLease see $LOGS_FILE"
        print "Firewall configuration is completed." 1
    fi
fi

print "Bitrix Environment $BX_PACKAGE installation is completed." 1
[[ $TEST_REPOSITORY -eq 0 ]] && rm -f $LOGS_FILE
