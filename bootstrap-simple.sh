#!/bin/bash

#getOS=`cat /etc/*-release |grep "^NAME"| sed 's/NAME="\(.*\)"/\1/g'`

if [[ $(id -u) -ne 0 ]];
  then echo "Linux bootstrapper, Setting all the things -- run as root...";
  exit 1;
fi

timezone="Asia/Taipei"

exec > >(tee /var/log/install.log)
exec 2>&1

function file_update() { sed -i '\|$1|d' $2; echo $1 >> $2; }

#function file_touch() { mkdir -p `dirname $1`; touch $1; chmod $2 $1; }

function apt_update() { echo "==> Updating packages"
  file_update "deb http://archive.ubuntu.com/ubuntu/ `cat /etc/lsb-release | grep CODENAME | cut -d= -f2` main restricted universe multiverse" /etc/apt/sources.list
  file_update "deb http://archive.ubuntu.com/ubuntu/ `cat /etc/lsb-release | grep CODENAME | cut -d= -f2`-updates main restricted universe multiverse" /etc/apt/sources.list
  file_update "deb http://archive.canonical.com/ubuntu/ `cat /etc/lsb-release | grep CODENAME | cut -d= -f2` partner" /etc/apt/sources.list
  apt-get update -y 2>&1 >> /dev/null
  apt-get upgrade -y 2>&1 >> /dev/null
}

function yum_update() { echo "==> Updating packages"
  yum -y -q update
}

function sysconf() {
    echo 'fs.file-max=6553500' >> /etc/sysctl.conf
    echo 'net.ipv4.ip_local_port_range = 10240 65000' >> /etc/sysctl.conf
    echo 'net.ipv6.conf.all.disable_ipv6 = 1' >> /etc/sysctl.conf
    echo 'net.ipv6.conf.default.disable_ipv6 = 1' >> /etc/sysctl.conf
    echo 'net.ipv6.conf.lo.disable_ipv6 = 1' >> /etc/sysctl.conf
    sysctl -p
    echo '* - nofile 65535' >> /etc/security/limits.conf
    #echo '* soft nofile 1000000' >> /etc/security/limits.conf
    #echo '* hard nofile 1000000' >> /etc/security/limits.conf
    #echo 'session required pam_limits.so' >> /etc/pam.d/login # ubuntu 20.04 above version already include
    ulimit -n 1000000
    ulimit -n -H
    echo 1 > /proc/sys/net/ipv4/tcp_tw_reuse
    echo '1024' > /proc/sys/net/core/somaxconn
}

function os_ubuntu() { echo "==> Modifying OS parameters"
  if ! grep 'session required pam_limits' /etc/pam.d/login
  then
    locale-gen en_US.UTF-8
    sysconf
  fi
}

function os_centos() { echo "==> Modifying OS parameters"
  if ! grep 'session required pam_limits' /etc/pam.d/login
  then
    localectl set-locale LANG=en_US.UTF-8
    echo 'LANG=en_US.UTF-8' >> /etc/environment
    echo 'LC_ALL=en_US.UTF-8' >> /etc/environment
    sysconf
    echo "alias vi='vim'" >> ~/.bashrc
    systemctl stop firewalld
    systemctl disable firewalld
  fi
}

function ntp_ubuntu() { echo "==> Setting timezone"
  echo '$timezone' | tee /etc/timezone
  dpkg-reconfigure --frontend noninteractive tzdata
  cat - << EOF > /etc/cron.d/clock
0 0 * * * * root ntpdate ntp.ubuntu.com pool.ntp.org 2>&1 >> /dev/null
EOF
}

function ntp_centos() { echo "==> Setting timezone"
  yum install -y -q ntp
  timedatectl set-timezone $timezone
  ntpdate -s ntp.ubuntu.com
  cat - << EOF > /etc/cron.d/clock
0 0 * * * * root ntpdate ntp.ubuntu.com pool.ntp.org 2>&1 >> /dev/null
EOF
}

#function users() { echo "==> Check/add Ubuntu user"
#  if [ ! -d /home/ubuntu ]; then
#    useradd -d /home/ubuntu -m ubuntu
#    adduser ubuntu sudo
#    echo '%sudo ALL=NOPASSWD: ALL' >> /etc/sudoers
#    adduser ubuntu admin
#    chsh -s /bin/bash ubuntu
#  fi
#}

function software_ubuntu() { echo "==> Install usuall used software" 
  apt-get -y install htop screen snmpd unzip chrony
}

function software_centos() { echo "==> Install usuall used software" 
  yum -y -q install epel-release ; yum -y -q update
  yum -y -q install htop net-snmp unzip screen net-tools vim
}

function cleanup_ubuntu() { echo "==> Cleanup Install" 
  apt-get autoremove -y
}

function cleanup_centos() { echo "==> Cleanup Install" 
  yum clean all
  yum remove -y -q postfix
}

function message() {
  echo "############################################################"
  echo "Setting Done."
  echo "############################################################"
}

# configure and deploy
while read OSver ; do
    case "$OSver" in
        Ubuntu)
          echo "Prepare For $OSver environment"
          export DEBIAN_FRONTEND=noninteractive
          echo 'debconf debconf/frontend select Noninteractive' | sudo debconf-set-selections
          export DEBIAN_PRIORITY=critical
          apt_update
          os_ubuntu
          #ntp_ubuntu
          software_ubuntu
          cleanup_ubuntu
          message
          ;;
        CentOS)
          echo "Prepare For $OSver environment"
          yum_update
          os_centos
          ntp_centos
          software_centos
          cleanup_centos
          message
          ;;
        *) # unsupported flags
          echo "Error: Unsupported OS Version $OSver" >&2
          exit 1
          ;;
    esac
done <<< "$(cat /etc/*-release |grep "^NAME"| sed 's/NAME="\(.*\)"/\1/g' | awk -F" " '{print $1}')"
