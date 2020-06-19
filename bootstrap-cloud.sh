#~/bin/bash

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
    echo 'session required pam_limits.so' >> /etc/pam.d/login
    ulimit -n 1000000
    ulimit -n -H
    echo 1 > /proc/sys/net/ipv4/tcp_tw_reuse
    echo '10240' > /proc/sys/net/core/somaxconn
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
    #source ~/.bashrc
    systemctl stop firewalld
    systemctl disable firewalld
  fi
}

function ntp_ubuntu() { echo "==> Setting timezone" 
  echo '$timezone' | tee /etc/timezone
  dpkg-reconfigure --frontend noninteractive tzdata
  cp /usr/share/zoneinfo/Asia/Taipei /etc/localtime
  apt install -y chrony
  #cat - << EOF > /etc/cron.d/clock
#0 0 * * * * root ntpdate ntp.ubuntu.com pool.ntp.org 2>&1 >> /dev/null
#EOF
}

function ntp_centos() { echo "==> Setting timezone" 
  yum install -y -q chrony
  #yum install -y -q ntp
  timedatectl set-timezone $timezone
  systemctl enable chronyd.service ; systemctl start chronyd.service
  #ntpdate -s ntp.ubuntu.com
  #cat - << EOF > /etc/cron.d/clock
#0 0 * * * * root ntpdate ntp.ubuntu.com pool.ntp.org 2>&1 >> /dev/null
#EOF
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

#function firewall() { echo "==> Create Firewall Scripts"
#  mkdir /etc/firewall/
#  cat - << EOF > /etc/firewall/def.sh
#  #!/bin/bash
#  #
#  # Firewall
#  #
#  
#  # Flush All Rules and Delete All Custom Chains
#  iptables -F
#  iptables -X
#  iptables -t nat -F
#  iptables -t nat -X
#  
#  # Set Up Policies
#  iptables -P INPUT      ACCEPT
#  iptables -P OUTPUT     ACCEPT
#  iptables -P FORWARD    ACCEPT
#EOF
#
#  chmod +x /etc/firewall/def.sh
#  
#  cat - << EOF > /etc/firewall/firewall.sh
#  #!/bin/bash
#  #
#  # Firewall
#  #
#  
#  # Flush All Rules and Delete All Custom Chains
#  iptables -F
#  iptables -X
#  iptables -t nat -F
#  iptables -t nat -X
#  
#  # Set Up Policies
#  iptables -P INPUT      DROP
#  iptables -P OUTPUT     ACCEPT
#  iptables -P FORWARD    DROP
#  
#  #Allowing Established Sessions
#  iptables -A INPUT   -m state --state ESTABLISHED,RELATED -j ACCEPT
#  iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
#  
#  iptables -A INPUT  -i lo -j ACCEPT
#  iptables -A OUTPUT -o lo -j ACCEPT
#  
#  #iptables -A FORWARD -s 10.0.120.0/24 -j ACCEPT
#  
#  #Allowing Incoming Traffic on Specific Ports
#  #iptables -A INPUT -p tcp -s Internal-IP-prefix -j ACCEPT
#  iptables -A INPUT -p tcp -s 59.124.224.242 -j ACCEPT
#  
#  iptables -A INPUT -p tcp --dport 80 -j ACCEPT
#  iptables -A INPUT -p udp -m multiport --dports 123,161 -j ACCEPT
#  
#  #Allowing ICMP
#  iptables -A INPUT -p icmp -j ACCEPT
#  
#EOF
#  
#  chmod +x /etc/firewall/firewall.sh
#
#}

#function CommandLog() { echo "==> Enable User Command Log"
#  cat - << EOF >> /etc/profile
#  # Command Log Record
#  HisFolder="/var/log/.history"
#  USER=\`whoami\`
#  USER_IP=\`who -u am i 2>/dev/null| awk '{print \$NF}'|sed -e 's/[()]//g'\`
#  if [ "\$USER_IP" = "" ]; then
#    USER_IP=`hostname`
#  fi
#  if [ ! -d \$HisFolder ]; then
#    mkdir \$HisFolder
#    chmod 777 \$HisFolder
#  fi
#  if [ ! -d \$HisFolder/\${LOGNAME} ]; then
#    mkdir \$HisFolder/\${LOGNAME}
#    chmod 300 \$HisFolder/\${LOGNAME}
#  fi
#  export HISTSIZE=4096
#  DT=\`date +"%Y%m%d_%H:%M:%S"\`
#  export HISTFILE="\$HisFolder/\${LOGNAME}/\${USER}@\${USER_IP}_\$DT"
#  chmod 600 \$HisFolder/\${LOGNAME}/*history* 2>/dev/null
#EOF
#}

function software_ubuntu() { echo "==> Install usuall used software" 
  apt-get -y install htop screen snmpd unzip
}

function software_centos() { echo "==> Install usuall used software" 
  yum -y -q install epel-release ; yum -y -q update
  yum -y -q install htop net-snmp unzip screen net-tools vim
}

function cleanup_ubuntu() { echo "==> Cleanup Install" 
  apt-get autoremove -y
  updatedb
}

function cleanup_centos() { echo "==> Cleanup Install" 
  yum clean all
  yum remove -y -q postfix
}

function message() {
  echo "############################################################"
  echo "Setting Done."
  echo "Firewall Policy already added. If want to enable afert boot."
  echo "Please modify your rc.local file."
  echo "############################################################"
}

# configure and deploy
while read OSver ; do
    case "$OSver" in
        Ubuntu)
          echo "Prepare For $OSver environment"
          export DEBIAN_FRONTEND=noninteractive
          export DEBIAN_PRIORITY=critical
          apt_update
          os_ubuntu
          ntp_ubuntu
          #firewall
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
          #firewall
          cleanup_centos
          message
          ;;
        *) # unsupported flags
          echo "Error: Unsupported OS Version $OSver" >&2
          exit 1
          ;;
    esac
done <<< "$(cat /etc/*-release |grep "^NAME"| sed 's/NAME="\(.*\)"/\1/g' | awk -F" " '{print $1}')"
