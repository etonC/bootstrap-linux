#~/bin/bash



getOS=`cat /etc/*-release |grep "^NAME"| sed 's/NAME="\(.*\)"/\1/g'`

if [[ $(id -u) -ne 0 ]]; 
  then echo "Linux bootstrapper, Setting all the things -- run as root...";
  exit 1; 
fi



exec > >(tee /var/log/install.log)
exec 2>&1
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

function file_update() { sed -i '\|$1|d' $2; echo $1 >> $2; }

#function file_touch() { mkdir -p `dirname $1`; touch $1; chmod $2 $1; }

function apt() { echo "==> Updating packages" 
  file_update "deb http://archive.ubuntu.com/ubuntu/ `cat /etc/lsb-release | grep CODENAME | cut -d= -f2` main restricted universe multiverse" /etc/apt/sources.list
  file_update "deb http://archive.ubuntu.com/ubuntu/ `cat /etc/lsb-release | grep CODENAME | cut -d= -f2`-updates main restricted universe multiverse" /etc/apt/sources.list
  file_update "deb http://archive.canonical.com/ubuntu/ `cat /etc/lsb-release | grep CODENAME | cut -d= -f2` partner" /etc/apt/sources.list
  apt-get update -y 2>&1 >> /dev/null
  apt-get upgrade -y 2>&1 >> /dev/null
}

function os_ubunt() { echo "==> Modifying OS parameters"
  if ! grep 'session required pam_limits' /etc/pam.d/login
  then
    locale-gen en_US.UTF-8
    cd /opt
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
  fi
}

function ntp() { echo "==> Setting timezone" 
  echo 'Asia/Taipei' | tee /etc/timezone
  dpkg-reconfigure --frontend noninteractive tzdata
  cat - << EOS > /etc/cron.d/clock
0 0 * * * * root ntpdate ntp.ubuntu.com pool.ntp.org 2>&1 >> /dev/null
EOS
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

function firewall() { echo "==> Create Firewall Scripts"
  mkdir /etc/firewall/
  cat - << EOF > /etc/firewall/def.sh
  #!/bin/bash
  #
  # Firewall
  #
  
  # Flush All Rules and Delete All Custom Chains
  iptables -F
  iptables -X
  iptables -t nat -F
  iptables -t nat -X
  
  # Set Up Policies
  iptables -P INPUT      ACCEPT
  iptables -P OUTPUT     ACCEPT
  iptables -P FORWARD    ACCEPT
EOF

  chmod +x /etc/firewall/def.sh
  
  cat - << EOF > /etc/firewall/firewall.sh
  #!/bin/bash
  #
  # Firewall
  #
  
  # Flush All Rules and Delete All Custom Chains
  iptables -F
  iptables -X
  iptables -t nat -F
  iptables -t nat -X
  
  # Set Up Policies
  iptables -P INPUT      DROP
  iptables -P OUTPUT     ACCEPT
  iptables -P FORWARD    DROP
  
  #Allowing Established Sessions
  iptables -A INPUT   -m state --state ESTABLISHED,RELATED -j ACCEPT
  iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
  
  iptables -A INPUT  -i lo -j ACCEPT
  iptables -A OUTPUT -o lo -j ACCEPT
  
  #iptables -A FORWARD -s 10.0.120.0/24 -j ACCEPT
  
  #Allowing Incoming Traffic on Specific Ports
  #iptables -A INPUT -p tcp -s Internal-IP-prefix -j ACCEPT
  iptables -A INPUT -p tcp -s 59.124.224.242 -j ACCEPT
  
  iptables -A INPUT -p tcp --dport 80 -j ACCEPT
  iptables -A INPUT -p udp -m multiport --dports 123,161 -j ACCEPT
  
  #Allowing ICMP
  iptables -A INPUT -p icmp -j ACCEPT
  
EOF
  
  chmod +x /etc/firewall/firewall.sh

}

function Ubuntu_software() { echo "==> Install usuall used software" 
  apt-get -y htop screen snmpd unzip
}

function Ubuntu_cleanup() { echo "==> Cleanup Install" 
  apt-get autoremove -y
  updatedb
}

# configure and deploy
while read OSver; do
    case "$OSver" in
        Ubuntu)
          echo "Prepare For $OSver environment"
        	apt
			os_ubunt
			ntp
			firewall
			Ubuntu_software
			Ubuntu_cleanup
            ;;
        CentOS)
          echo "Prepare For $OSver environment"
			ntp
			firewall
            ;;
        *) # unsupported flags
            echo "Error: Unsupported OS Version $OSver" >&2
            exit 1
            ;;
    esac
done <<< "$(cat /etc/*-release |grep "^NAME"| sed 's/NAME="\(.*\)"/\1/g' | awk -F" " '{print $1}')"
