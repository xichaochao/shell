#!/bin/bash
# The script was improved by zxc
# Yum is required for installation
# Please ensure that port 389 80 is not occupied,
# If port 80 occupied，Modify /etc/httpd/conf/httpd.conf
# /etc/sysconfig/ldap  389
# pay close attention!!
# Variable declaration
PASSWD_admin=123456
DOMAIN="dc=zxc,dc=com"
DN="cn=admin,dc=zxc,dc=com"
OR=zxc

yum -y install openldap compat-openldap openldap-clients openldap-servers openldap-servers-sql openldap-devel migrationtools
yum install -y epel-release 
#############################################
# Create a database configuration file
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown ldap:ldap /var/lib/ldap/*
systemctl enable slapd && systemctl start slapd
##################################
# Set the OpenLDAP administrator password
ldap_admin=$(slappasswd -s $PASSWD_admin)
cat > /root/changepwd.ldif <<-EOF
dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: $ldap_admin
EOF
ldapadd -Y EXTERNAL -H ldapi:/// -f  /root/changepwd.ldif
###############################################
# Import the default mode
ls /etc/openldap/schema/*.ldif | while read f; do ldapadd -Y EXTERNAL -H ldapi:/// -f $f; done
#################################################
# Create a new root
# Generate a domain 
cat > /root/changedomain.ldif <<-EOF
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="$DN" read by * none

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: $DOMAIN

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: $DN

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $ldap_admin

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by dn="$DN" write by anonymous auth by self write by * none
olcAccess: {1}to dn.base="" by * read
olcAccess: {2}to * by dn="$DN" write by * read
EOF
ldapmodify -Y EXTERNAL -H ldapi:/// -f /root/changedomain.ldif
######################################################
# Add user and group 
cat > /root/add-memberof.ldif <<-EOF
dn: cn=module{0},cn=config
cn: modulle{0}
objectClass: olcModuleList
objectclass: top
olcModuleload: memberof.la
olcModulePath: /usr/lib64/openldap

dn: olcOverlay={0}memberof,olcDatabase={2}hdb,cn=config
objectClass: olcConfig
objectClass: olcMemberOf
objectClass: olcOverlayConfig
objectClass: top
olcOverlay: memberof
olcMemberOfDangling: ignore
olcMemberOfRefInt: TRUE
olcMemberOfGroupOC: groupOfUniqueNames
olcMemberOfMemberAD: uniqueMember
olcMemberOfMemberOfAD: memberOf
EOF
ldapadd -Q -Y EXTERNAL -H ldapi:/// -f /root/add-memberof.ldif

echo "dn: cn=module{0},cn=config
add: olcmoduleload
olcmoduleload: refint
" > /root/refint1.ldif

ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /root/refint1.ldif

echo "dn: olcOverlay=refint,olcDatabase={2}hdb,cn=config
objectClass: olcConfig
objectClass: olcOverlayConfig
objectClass: olcRefintConfig
objectClass: top
olcOverlay: refint
olcRefintAttribute: memberof uniqueMember  manager owner
" > /root/refint2.ldif

ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /root/refint2.ldif

echo "dn: $DOMAIN
objectClass: top
objectClass: dcObject
objectClass: organization
o: $OR Company
dc: $OR

dn: $DN
objectClass: organizationalRole
cn: admins

dn: ou=People,$DOMAIN
objectClass: organizationalUnit
ou: People

dn: ou=Group,$DOMAIN
objectClass: organizationalRole
cn: Group
" > /root/base.ldif

ldapadd -x -D $DN -w $PASSWD_admin -f /root/base.ldif


echo "dn: cn=config
changetype: modify
add: olcLogLevel
olcLogLevel: 32" > /root/log.ldif

ldapmodify -Y EXTERNAL -H ldapi:/// -f /root/log.ldif

mkdir -p /var/log/slapd
chown ldap:ldap /var/log/slapd/
echo "local4.* /var/log/slapd/slapd.log" >> /etc/rsyslog.conf
systemctl enable rsyslog
systemctl restart rsyslog
######################################
# this is ok !!!!!!!!!
# clearn LDIF file

##################################
#################################
#  install Graphical management tool

yum -y install httpd-2.4.6-97.el7.centos.5

#
httpd_Line_number=$(grep  -n  "Directory \/" /etc/httpd/conf/httpd.conf |awk -F ":" '{print $1}')
sed -i -e "$httpd_Line_number,$[$httpd_Line_number + 7]s/none/all/g" -e "$httpd_Line_number,$[$httpd_Line_number + 7]s/Require/#Require/"  /etc/httpd/conf/httpd.conf



# phpldapadmin-1.2.5-1.el7
yum -y install  phpldapadmin-1.2.5-1.el7

sed -i  -e "s/\$servers->setValue('login','attr','uid'/#\$servers->setValue('login','attr','uid'/g"  -e '$d'  /etc/phpldapadmin/config.php

echo "\$servers->setValue('server','host','127.0.0.1');
\$servers->setValue('server','port',389);
\$servers->setValue('server','base',array('dc=jengcloud,dc=com'));  
\$servers->setValue('login','auth_type','session');
\$servers->setValue('login','attr','dn'); 
?>" >> /etc/phpldapadmin/config.php

echo "Alias /phpldapadmin /usr/share/phpldapadmin/htdocs
Alias /ldapadmin /usr/share/phpldapadmin/htdocs

<Directory /usr/share/phpldapadmin/htdocs>
  <IfModule mod_authz_core.c>
    # Apache 2.4
    Require local
    Require all granted
  </IfModule>
  <IfModule !mod_authz_core.c>
    # Apache 2.2
    Order Deny,Allow
#    Deny from all
#    Allow from 127.0.0.1
    Allow from all
  </IfModule>
</Directory>
" > /etc/httpd/conf.d/phpldapadmin.conf

systemctl start httpd.service 
systemctl enable httpd.service
systemctl restart httpd.service

 echo -e "
 login address: http://IP/phpldapadmin
 DN:cn=admin,dc=jengcloud,dc=com
 passwd: $PASSWD_admin "
