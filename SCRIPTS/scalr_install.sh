#!/bin/bash

# Runs as root via sudo

exec 1>/var/tmp/$(basename $0).log

exec 2>&1

abort () {
  echo "ERROR: Failed with $1 executing '$2' @ line $3"
  exit $1
}

detect_os ()
{
  if [[ ( -z "${os}" ) && ( -z "${dist}" ) ]]; then
    if [ -e /etc/os-release ]; then
      . /etc/os-release
      os=${ID}
      if [ "${os}" = "poky" ]; then
        dist=`echo ${VERSION_ID}`
      elif [ "${os}" = "sles" ]; then
        dist=`echo ${VERSION_ID}`
      elif [ "${os}" = "opensuse" ]; then
        dist=`echo ${VERSION_ID}`
      elif [ "${os}" = "opensuse-leap" ]; then
        os=opensuse
        dist=`echo ${VERSION_ID}`
      else
        dist=`echo ${VERSION_ID} | awk -F '.' '{ print $1 }'`
      fi

    elif [ `which lsb_release 2>/dev/null` ]; then
      # get major version (e.g. '5' or '6')
      dist=`lsb_release -r | cut -f2 | awk -F '.' '{ print $1 }'`

      # get os (e.g. 'centos', 'redhatenterpriseserver', etc)
      os=`lsb_release -i | cut -f2 | awk '{ print tolower($1) }'`

    elif [ -e /etc/oracle-release ]; then
      dist=`cut -f5 --delimiter=' ' /etc/oracle-release | awk -F '.' '{ print $1 }'`
      os='ol'

    elif [ -e /etc/fedora-release ]; then
      dist=`cut -f3 --delimiter=' ' /etc/fedora-release`
      os='fedora'

    elif [ -e /etc/redhat-release ]; then
      os_hint=`cat /etc/redhat-release  | awk '{ print tolower($1) }'`
      if [ "${os_hint}" = "centos" ]; then
        dist=`cat /etc/redhat-release | awk '{ print $3 }' | awk -F '.' '{ print $1 }'`
        os='centos'
      elif [ "${os_hint}" = "scientific" ]; then
        dist=`cat /etc/redhat-release | awk '{ print $4 }' | awk -F '.' '{ print $1 }'`
        os='scientific'
      else
        dist=`cat /etc/redhat-release  | awk '{ print tolower($7) }' | cut -f1 --delimiter='.'`
        os='redhatenterpriseserver'
      fi

    else
      aws=`grep -q Amazon /etc/issue`
      if [ "$?" = "0" ]; then
        dist='6'
        os='aws'
      else
        unknown_os
      fi
    fi
  fi

  if [[ ( -z "${os}" ) || ( -z "${dist}" ) ]]; then
    unknown_os
  fi

  # remove whitespace from OS and dist name
  os="${os// /}"
  dist="${dist// /}"

  echo "Detected operating system as ${os}/${dist}."

  if [ "${dist}" = "8" ]; then
    _skip_pygpgme=1
  else
    _skip_pygpgme=0
  fi
}

trap 'abort $? "$STEP" $LINENO' ERR

TOKEN="${1}"
DOMAIN_NAME="${2}"

STEP="Get device"
DEVICE=/dev/$(dmesg | grep SCSI | tail -1 | cut -d '[' -f 3 | cut -d ']' -f 1)

STEP="fdisk"
fdisk $DEVICE << !
n
p
1


p
w
!

DEVICE=${DEVICE}1

STEP="MKFS"
mkfs -t ext4 ${DEVICE}

STEP="mkdir"
mkdir /opt/scalr-server

STEP="mount /opt/scalr-server"
mount ${DEVICE} /opt/scalr-server
echo ${DEVICE}  /opt/scalr-server ext4 defaults,nofail 0 2 >> /etc/fstab

if which apt-get 2> /dev/null; then
  STEP="curl to down load repo"
  curl -s https://${TOKEN}:@packagecloud.io/install/repositories/scalr/scalr-server-ee-staging/script.deb.sh | bash

  STEP="apt-get install scalr-server"
  apt-get install -y scalr-server
else
  STEP="curl to down load repo"
  curl -s https://${TOKEN}:@packagecloud.io/install/repositories/scalr/scalr-server-ee-staging/script.rpm.sh | bash

  STEP="yum install scalr-server"
  yum -y install scalr-server
fi

STEP="scalr-server-wizard"
scalr-server-wizard

STEP=" Self-signed cert"
cp /var/tmp/my.crt /etc/scalr-server/organization.crt.pem
cp /var/tmp/my.key /etc/scalr-server/organization.key.pem

STEP="Create config with cat"

cat << ! > /etc/scalr-server/scalr-server.rb
enable_all true
product_mode :iacp

# Mandatory SSL
# Update the below settings to match your FQDN and where your .key and .crt are stored
proxy[:ssl_enable] = true
proxy[:ssl_redirect] = true
proxy[:ssl_cert_path] = "/etc/scalr-server/organization.crt.pem"
proxy[:ssl_key_path] = "/etc/scalr-server/organization.key.pem"

routing[:endpoint_host] = "$DOMAIN_NAME"
routing[:endpoint_scheme] = "https"

#Add if you have a self signed cert, update with the proper location if needed
#ssl[:extra_ca_file] = "/etc/scalr-server/rootCA.pem"

#Add if you require a proxy, it will be used for http and https requests
#http_proxy "http://user:*****@my.proxy.com:8080"

#If a no proxy setting is needed, you can define a domain or subdomain like so: no_proxy=example.com,domain.com . The following setting would not work: *.domain.com,*example.com
#no_proxy example.com

#If you are using an external database service or separating the database onto a different server.
#app[:mysql_scalr_host] = "$DB_HOST"
#app[:mysql_scalr_port] = 3306

#app[:mysql_analytics_host] = "$DB_HOST"
#app[:mysql_analytics_port] = 3306

####The following is only needed if you want to use a specific version of Terraform that Scalr may not included yet.####
#app[:configuration] = {
#:scalr => {
#  "tf_worker" => {
#      "default_terraform_version"=> "0.12.20",
#      "terraform_images" => {
#          "0.12.10" => "hashicorp/terraform:0.12.10",
#          "0.12.20" => "hashicorp/terraform:0.12.20"
#      }
#    }
#  }
#}
!

# Conditional because MySQL Master wont have it's local file yet

STEP="Create License"
cp /var/tmp/license.json /etc/scalr-server/license.json

STEP="scalr-server-ctl reconfigure"
scalr-server-ctl reconfigure

detect_os

STEP="Firewall stuff"
if [[ ${os}/${dist} == "rhel/7" ]]; then
  iptables -A IN_public_allow -p tcp --dport 443 -j ACCEPT
elif [[ ${os}/${dist} == "rhel/8" ]]; then
  firewall-cmd --zone=public --permanent --add-service=https
  firewall-cmd --reload
fi

exit 0
