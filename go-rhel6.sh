#!/bin/bash

IFS=$'\n'  # NE SURTOUT PAS SUPPRIMER ! Mettrait le script en vrac...

datacenter=""
showlist=0

# Variables
readonly LAST_HWVERSION_ESX5="9"
readonly LAST_HWVERSION_ESX6="11"
readonly RECETTE_REMOTE_REP="/tmp/recette"
readonly RECETTE_REMOTE_REF_REP="$RECETTE_REMOTE_REP/ref"
readonly RECETTE_REMOTE_REF_OPSCENTER_REP="$RECETTE_REMOTE_REP/ref/opscenter"
readonly VMWARE_HWVERSION_FILE="$RECETTE_REMOTE_REF_REP/hardversion-vmware.csv"
readonly VMWARE_ZONE_FILE="$RECETTE_REMOTE_REF_REP/zone-vmware.csv"
readonly VMWARE_VLAN_FILE="$RECETTE_REMOTE_REF_REP/vlan-vmware.csv"
readonly OPCA_VLAN_FILE="$RECETTE_REMOTE_REF_REP/vlan-opca.csv"
readonly OPCA_VLAN_TRE_FILE="$RECETTE_REMOTE_REF_REP/opca-tre.csv"
readonly OPCA_VLAN_OLL_FILE="$RECETTE_REMOTE_REF_REP/opca-oll.csv"
readonly OPSCENTER_FILES="$RECETTE_REMOTE_REF_OPSCENTER_REP/*.csv"
readonly NETBACKUP_CONFFILE="/usr/openv/netbackup/bp.conf"
readonly NETBACKUP_PORT="1556"
readonly NETBACKUP_TIMEOUT_CONNECTION="3s"
readonly SIZE_PERCENT="10" # 10%
readonly OK="OK"
readonly WARN="WARN"
readonly DOMAIN1="tethys.int"
readonly DOMAIN2="nemesis.sea"

source "$RECETTE_REMOTE_REP/config-toano.sh"  # Importer les variables à anonymiser

readonly NB_PUBKEYS=${#PUBKEYS[@]}

###### FONCTIONS

function showUsage {
   echo "Usage : go.sh -f <name> [-l]"
   echo "        name : Nom du fichier au format CSV avec point-virgules contenant la liste des serveurs (sans l'extension .csv)"
   echo "               Ce fichier doit etre situe ici ./csv/<name>/<name>.csv"
   echo "        -l   : Ne fait qu'afficher le contenu du fichier csv"
}

function recuperer_options {
   while getopts f:lsh argument
   do
    case ${argument} in
    f) datacenter=${OPTARG}
	   ;;
	l)
           showlist=1
	   ;;
	h)     showUsage
           exit 0
	   ;;
     esac
   done
}


###### MAIN

###### Récupération des options en entree et des données du csv

recuperer_options $*
readonly CSV_FILE="$RECETTE_REMOTE_REP/$datacenter.csv"  # Ne pas déplacer cette variable en haut car besoin d'argument du script

if [ -z $datacenter ]; then
   echo "Parametre -f obligatoire!"
   echo
   showUsage
   exit 255
fi
if [ ! -f $CSV_FILE ]; then
   echo "ERREUR : Fichier $CSV_FILE introuvable parmi :"
   ls -l csv/*.csv | awk -F" " '{print $9}'
   echo
   showUsage
   exit 255
fi

srce_mounted=0

for line in $(cat $CSV_FILE); do
   env=`echo $line | awk -F";" '{print $1}' | tr 'a-z' 'A-Z'` # recuperation environnement du serveur
   site=`echo $line | awk -F";" '{print $2}' | tr 'a-z' 'A-Z'` # recuperation location du serveur
   h=`echo $line | awk -F";" '{print $3}' | tr 'a-z' 'A-Z'` # recuperation nom du serveur
   t=`echo $line | awk -F";" '{print $4}' | tr 'a-z' 'A-Z'` # recuperation type du serveur (VM ou Physique)
   vm=0 && echo $t | grep -i VM >/dev/null && vm=1
   cpu=`echo $line | awk -F";" '{print $5}'` # recuperation nombre de CPU
   ram=`echo $line | awk -F";" '{print $6}'` # recuperation quantité de RAM
   swap=`echo $line | awk -F";" '{print $7}' | sed 's/[^0-9.]*//g'` # recuperation Swap
   [[ $swap == "" ]] && swap="-"
   nos=`echo $line | awk -F";" '{print $8}' | tr 'a-z' 'A-Z' | sed 's/[^A-Z]*//g' | cut -c 1-6` # recuperation nom OS
   nos_long=`echo $line | awk -F";" '{print $8}' | tr 'a-z' 'A-Z' | sed 's/[^A-Z ]*//g' | sed 's/RED HAT/REDHAT/g' | sed 's/  / /g'` # recuperation nom OS
   os=`echo $line | awk -F";" '{print $8}' | sed 's/[^0-9.]*//g'` # recuperation version OS
   durci=`echo $line | awk -F";" '{print $8}' | grep -i durci >/dev/null 2>&1 && echo 1 || echo 0` # recuperation OS durci ?
   zone=`echo $line | awk -F";" '{print $9}'` # recuperation Zone de confiance
   vlan_svc=`echo $line | awk -F";" '{print $10}'` # recuperation VLAN SVC
   ip_svc=`echo $line | awk -F";" '{print $11}'` # recuperation IP SVC
   vlan_nas=`echo $line | awk -F";" '{print $12}'` # recuperation VLAN NAS
   [[ $vlan_nas == "" || $vlan_nas == "0" ]] && vlan_nas="-"
   ip_nas=`echo $line | awk -F";" '{print $13}'` # recuperation IP NAS
   [[ $ip_nas == "" || $ip_nas == "0" ]] && ip_nas="-"
   vlan_sau=`echo $line | awk -F";" '{print $14}'` # recuperation VLAN SAU
   ip_sau=`echo $line | awk -F";" '{print $15}'` # recuperation IP SAU
   vlan_adm=`echo $line | awk -F";" '{print $16}'` # recuperation VLAN ADM
   ip_adm=`echo $line | awk -F";" '{print $17}'` # recuperation IP ADM
   #fs=`echo $line | awk -F";" '{print $18}'` # recuperation FS


###### Affichage des données du csv

printf "%-15s %15s %15s %15s %5s %5s %5s %25s %8s %4s %24s %24s %24s %24s\n" "NOM" "ENVIRONNEMENT" "SITE" "TYPE" "CPU" "RAM" "SWAP" "NOM OS" "v.OS" "ZONE" "IPSVC (VLAN)" "IPSAU (VLAN)" "IPADM (VLAN)" "IPNAS (VLAN)"
printf "$TITLE%-15s %15s %15s %15s %5s %5s %5s %25s %8s %4s %24s %24s %24s %24s\n" $h $env $site $t $cpu $ram $swap $nos_long $os $zone "$ip_svc ($vlan_svc)" "$ip_sau ($vlan_sau)" "$ip_adm ($vlan_adm)" "$ip_nas ($vlan_nas)"
printf "\n"


###### Creation fichier csv avec les FS - OLD VERSION (décommenter variable fs ci-dessus aussi)

# res="${fs//[^#]}"
# nbfile="${#res}"
# ((nbfile+=1))
# i=1

# printf "%-45s %25s" "### Creation fichier csv avec volumetrie" " $h-FS.csv ... "
# >$RECETTE_REMOTE_REP/$h-FS.csv
# while [ $i -le $nbfile ]
# do
  # echo $fs | awk -F'#' -v NUSR=$i '{ print $NUSR}' >> $RECETTE_REMOTE_REP/$h-FS.csv
  # ((i+=1))
# done
# sed -i 's#[\"]##g' $RECETTE_REMOTE_REP/$h-FS.csv  # Suppression des guillemets dans le fichier temporaire FS
# printf "%-10s\n" " $OK"


###### Creation fichier csv avec les FS - NEW VERSION (Se réfère à la norme des FS système du client plutôt qu'au DIT)

printf "%-45s %25s" "### Creation fichier csv avec volumetrie" " $h-FS.csv ... "
printf "/ 14G\n/boot 0.5G\n/tmp 8G\n/var 8G\n/comp 10G" >$RECETTE_REMOTE_REP/$h-FS.csv
printf "%-10s\n" " $OK"


###### Check Depot YUM

stat="NOK"
yum repolist >/dev/null 2>&1
[[ $? -eq 0 ]] && stat="OK"
printf "%-50s %20s %-50s\n" "### Check Depot YUM" " ... " $stat


###### Package facter non installé -> installation"

# facter >/dev/null 2>&1
# if [ $? -eq 127 ]; then
    # stat="OK"
    # yum -y install facter >/dev/null 2>&1
    # facter >/dev/null 2>&1
    # [[ $? -ne 0 ]] && stat="NOK"
    # printf "%-50s %20s %-50s\n" "### Package facter non installé -> installation" " ... " $stat
# fi 


###### Check Virtual/Physical

# stat="NOK" && virtual=0
# facter | grep virtual | grep true >/dev/null 2>&1
# [[ $? -eq 0 ]] && [[ $vm -eq 1 ]] && stat="OK" && virtual=1
# printf "%-50s %20s %-50s\n" "### Check Virtual/Physical" "[$t] ... " $stat


###### Check Virtual/Physical

echo $nos | grep -i -e 'OPCA' -e 'ORACLE' >/dev/null 2>&1
if [ $? -eq 1 ]; then
    stat="NOK" && virtual=0
    dmidecode -s system-product-name | grep VMware >/dev/null 2>&1
    [[ $? -eq 0 ]] && [[ $vm -eq 1 ]] && stat="OK" && virtual=1
    printf "%-50s %20s %-50s\n" "### Check Virtual/Physical" "[$t] ... " $stat
else
    stat="NOK" && virtual=0
    dmidecode -s system-product-name | grep HVM >/dev/null 2>&1
    [[ $? -eq 0 ]] && [[ $vm -eq 1 ]] && stat="OK" && virtual=1
    printf "%-50s %20s %-50s\n" "### Check Virtual/Physical" "[$t] ... " $stat
fi 
   

###### Check VMware Tools status

if [ $virtual -eq 1 ]; then
  echo $nos | grep -i -e 'OPCA' -e 'ORACLE' >/dev/null 2>&1
  if [ $? -eq 1 ]; then
     tools_status=$(cat $VMWARE_HWVERSION_FILE | grep -i $h | head -1 | awk -F';' '{print $3}' | sed 's#[\"]##g')
     stat="NOK"
     cat $VMWARE_HWVERSION_FILE | grep -i $h | grep -i 'guestToolsCurrent' >/dev/null 2>&1
     [[ $? -eq 0 ]] && stat="OK"
     printf "%-40s %30s %-50s\n" "### Check VMware Tools status" "$tools_status ... " $stat
     
     
 ###### Check VMware Hardware Version    
     
     hwversion=$(cat $VMWARE_HWVERSION_FILE | grep -i $h | head -1 | awk -F';' '{print $4}' | sed 's/[^0-9]*//g')
     stat="NOK"
     vcenter=$(cat $VMWARE_HWVERSION_FILE | grep -i $h | head -1 | awk -F';' '{print $1}' | sed 's#[\"]##g')
     [[ $vcenter == $VCENTER_V5 ]] && last_hwversion=$LAST_HWVERSION_ESX5 || last_hwversion=$LAST_HWVERSION_ESX6 
     cat $VMWARE_HWVERSION_FILE | grep -i $h | head -1 | grep $last_hwversion >/dev/null 2>&1
     [[ $? -eq 0 ]] && stat="OK"
     printf "%-40s %30s %-50s\n" "### Check VMware Hardware Version" "[$hwversion] ... " $stat
  fi
fi


###### Check CPU

stat="NOK"
res=$(cat /proc/cpuinfo | grep -i processor | wc -l)
[[ $res -eq $cpu ]] && stat="OK"
printf "%-50s %20s %-50s\n" "### Check CPU" "[$cpu] ... " $stat


###### Check RAM

stat="NOK"
divide=$(cat /proc/meminfo | grep -i MemTotal | sed 's/[^0-9]*//g')
# res=$(expr $res / $ram) && res=$(expr $res \* 1024) && res=$(expr $res / 1000000000)
by=1000000; (( result=(divide+by-1)/by )); 
res=$(expr $result / $ram)
[[ $res -eq 1 ]] && stat="OK"
printf "%-50s %20s %-50s\n" "### Check RAM" "[$ram] ... " $stat


###### Check SWAP
# Comme il n'y a pas de colonne de swap dans le DIT, le script est juste là pour faire un warning pour que l'on puisse vérifier que le serveur a bien du swap

stat="OK"
res=$(free -k | grep -i swap | awk -F' ' '{ print $2 }')
res=$(expr $res \* 1024) && res=$(expr $res / 1000000000)
if [[ $res -lt 2 ]]; then
  stat="NOK"
fi
printf "%-50s %20s %-50s\n" "### Check SWAP" "$res vs [$swap] ... " $stat


###### Check nom OS

# stat="NOK"
# res=$(facter | grep 'operatingsystem ' | awk -F' ' '{print $3}' | tr 'a-z' 'A-Z')
# echo $res | grep -i $nos >/dev/null 2>&1
# [[ $? -eq 0 ]] && stat="OK"
# printf "%-50s %20s %-50s\n" "### Check nom OS" "[$nos] ... " $stat


###### Check nom OS

echo $nos | grep -i -e 'OPCA' -e 'ORACLE' >/dev/null 2>&1
if [ $? -eq 1 ]; then
    stat="NOK"
    res=$(cat /etc/redhat-release | awk -F' ' '{print $1$2}' | tr 'a-z' 'A-Z')
    echo $res | grep -i $nos >/dev/null 2>&1
    [[ $? -eq 0 ]] && stat="OK"
    printf "%-50s %20s %-50s\n" "### Check nom OS" "[$nos] ... " $stat

else
    stat="NOK"
    res=$(cat /etc/oracle-release | awk -F' ' '{print $1$2}' | tr 'a-z' 'A-Z')
    echo $res | grep -i $nos >/dev/null 2>&1
    [[ $? -eq 0 ]] && stat="OK"
    printf "%-50s %20s %-50s\n" "### Check nom OS" "[$nos] ... " $stat

fi 


###### Check version OS

stat="NOK"
cat /etc/redhat-rel* | grep '6.5' >/dev/null 2>&1
[[ $? -eq 0 ]] && stat="OK"
printf "%-50s %20s %-50s\n" "### Check version OS" "[$os] ... " $stat


###### Check Zone de confiance
# Le script va chercher s'il trouve le nom du serveur dans une ligne où 
# - Pour VMware CP0' et OLL : le nom du datastore ne contient pas la zone de confiance
# - Pour OPCA : le nom des VLAN de la VM ne contient pas la zone de confiance
# et s'il en trouve c'est que la VM est dans un DS ou une de ses cartes est sur un VLAN qui n'est pas de sa ZDC et il va afficher "datastore(s) et/ou vmnic(s) pas dans la bonne zone"
# Pour VMware CP0, ça ne fonctionne pas car les DS ne sont pas nommés avec la ZDC (il faudra adapter le script pour qu'il check dans un fichier qui export les VLAN)
# Note : D6 = IN


is_serv_on_p1=$(cat $VMWARE_ZONE_FILE | grep -i $h | head -1 | awk -F";" '{print $1}' )
if [[ $is_serv_on_p1 == "\"p1-esx000vcsapp\"" ]]
    then
        stat="WARN ($h est sur vCenter CP0 -> Vérifiez manuellement les noms des VLAN)"
    else
        is_serv_in_exports=$(cat $OPCA_VLAN_TRE_FILE $OPCA_VLAN_OLL_FILE $VMWARE_ZONE_FILE | grep -i $h | wc -l)
        if [ $is_serv_in_exports -eq 0 ]
            then
                stat="WARN ($h non présent dans les exports)"
            else
                if [ "$zone" == "D6" ]
                    then
                       nb_zone_ko=$(cat $OPCA_VLAN_TRE_FILE $OPCA_VLAN_OLL_FILE $VMWARE_ZONE_FILE | grep -i $h | grep -v $zone | grep -v "IN" | wc -l)
                    else
                       nb_zone_ko=$(cat $OPCA_VLAN_TRE_FILE $OPCA_VLAN_OLL_FILE $VMWARE_ZONE_FILE | grep -i $h | grep -v $zone | wc -l) 
                fi
                stat="NOK ($nb_zone_ko datastore(s) et/ou vmnic(s) pas dans la bonne zone)"
                [[ $nb_zone_ko -eq 0 ]] && stat="OK"
        fi
fi

printf "%-50s %20s %-50s\n" "### Check Zone de confiance" "[$zone] ... " $stat


###### Check VLAN ID

cat $OPCA_VLAN_TRE_FILE $OPCA_VLAN_OLL_FILE > $OPCA_VLAN_FILE

is_serveur_in_exports=$(cat $OPCA_VLAN_FILE $VMWARE_VLAN_FILE | grep -i $h | wc -l)
if [ $is_serveur_in_exports -eq 0 ]
    then
        stat="WARN ($h non présent dans les exports)"
        printf "%-45s %25s %-50s\n" "### Check VLAN SVC" "[$vlan_svc] ... " $stat 
        printf "%-45s %25s %-50s\n" "### Check VLAN SAU" "[$vlan_sau] ... " $stat 
        printf "%-45s %25s %-50s\n" "### Check VLAN ADM" "[$vlan_adm] ... " $stat 
        printf "%-45s %25s %-50s\n" "### Check VLAN NAS" "[$vlan_nas] ... " $stat 
    else
        echo $nos | grep -i -e 'OPCA' -e 'ORACLE' >/dev/null 2>&1
        [[ $? -eq 0 ]] && vlanfile=$OPCA_VLAN_FILE || vlanfile=$VMWARE_VLAN_FILE

        ###### Check VLAN SVC

        stat="NOK"
        cat $vlanfile | grep -i $h | grep -i $vlan_svc >/dev/null 2>&1
        [[ $? -eq 0 ]] && stat="OK"
        [[ "$stat" != $OK ]]
        printf "%-45s %25s %-50s\n" "### Check VLAN SVC" "[$vlan_svc] ... " $stat 


        ###### Check VLAN SAU

        stat="NOK"
        cat $vlanfile | grep -i $h | grep -i $vlan_sau >/dev/null 2>&1
        [[ $? -eq 0 ]] && stat="OK"
        printf "%-45s %25s %-50s\n" "### Check VLAN SAU" "[$vlan_sau] ... " $stat


        ###### Check VLAN ADM

        stat="NOK"
        cat $vlanfile | grep -i $h | grep -i $vlan_adm >/dev/null 2>&1
        [[ $? -eq 0 ]] && stat="OK"
        printf "%-45s %25s %-50s\n" "### Check VLAN ADM" "[$vlan_adm] ... " $stat 


        ###### Check VLAN NAS

        if [ $ip_nas != "-" ]
            then
                stat="NOK"
                cat $vlanfile | grep -i $h | grep -i $vlan_nas >/dev/null 2>&1
                [[ $? -eq 0 ]] && stat="OK"
                printf "%-45s %25s %-50s\n" "### Check VLAN NAS" "[$vlan_nas] ... " $stat 
            else
                printf "%-45s %25s\n" "### Check VLAN NAS" "[$ip_nas] " 
        fi
fi  


###### Check IP SVC (ping gateway)

gateway=" "
tmp=$(ifconfig | grep -B1 $ip_svc)
res=$(echo $tmp | awk -F' ' '{print $1}' | head -1)
[[ $tmp && $res ]] && gateway=$(netstat -r | grep UG | grep $res | head -1 | awk -F' ' '{print $2}')
stat="NOK"
ping -c1 -w1 $gateway >/dev/null 2>&1
[[ $? -eq 0 ]] && stat="OK"
# cas de la passerelle 0.0.0.0
[[ $gateway == "*" ]] && stat="OK"
printf "%-45s %25s %-50s\n" "### Check IP SVC (ping gateway)" "$res:$gateway ... " $stat


###### Check IP SAU (port $NETBACKUP_PORT)

stat="NOK"
error=0 
test -e $NETBACKUP_CONFFILE
if [[ $? -eq 0 ]]
    then
        for netbackup in $(cat $NETBACKUP_CONFFILE | grep SERVER | grep "\-s" | awk -F "=" '{ print $2}' | sed "s# ##g"); do
          timeout $NETBACKUP_TIMEOUT_CONNECTION bash -c "exec 3<>/dev/tcp/$netbackup/$NETBACKUP_PORT >/dev/null 2>&1"
          [[ $? -ne 0 ]] && ((error++)) && stat="$stat"
          exec 3<&-
        done
        if [[ $error -eq 0 ]] 
            then
                stat="OK"
            else
                stat="NOK ($error des serveurs NBU non joignables)"
        fi
    else
        stat="NOK (Fichier $NETBACKUP_CONFFILE absent)"
fi
printf "%-45s %25s %-50s\n" "### Check IP SAU (port $NETBACKUP_PORT)" " ... " $stat


###### Check IP ADM (ping gateway)

gateway=" "
tmp=$(ifconfig | grep -B1 $ip_adm)
res=$(echo $tmp | awk -F' ' '{print $1}' | head -1)
[[ $tmp && $res ]] && gateway=$(netstat -r | grep UG | grep $res | head -1 | awk -F' ' '{print $2}')
stat="NOK"
ping -c1 -w1 $gateway >/dev/null 2>&1
[[ $? -eq 0 ]] && stat="OK"
# cas de la passerelle 0.0.0.0
[[ $gateway == "*" ]] && stat="OK"
printf "%-45s %25s %-50s\n" "### Check IP ADM (ping gateway)" "$res:$gateway ... " $stat


###### Check IP NAS (ping gateway)

if [ $ip_nas != "-" ]; then
  gateway=" "
  tmp=$(ifconfig | grep -B1 $ip_nas)
  res=$(echo $tmp | awk -F' ' '{print $1}' | head -1)
  [[ $tmp && $res ]] && gateway=$(netstat -rn | grep U | grep $res | head -1 | awk -F' ' '{print $2}')
  stat="NOK"
  ping -c1 -w1 $gateway >/dev/null 2>&1
  [[ $? -eq 0 ]] && stat="OK"
  # cas de la passerelle 0.0.0.0
  [[ $gateway == "0.0.0.0" ]] && stat="WARN"

  [[ "$stat" == $WARN ]]
  printf "%-45s %25s %-50s\n" "### Check IP NAS (ping gateway)" "$res:$gateway ... " $stat
else
  printf "%-45s %25s\n" "### Check IP NAS (ping gateway)" "[$ip_nas] "
fi


###### Check IP SVC (ifconfig)

stat="NOK"
ifconfig | grep $ip_svc >/dev/null 2>&1
[[ $? -eq 0 ]] && stat="OK"
printf "%-45s %25s %-50s\n" "### Check IP SVC (ifconfig)" "[$ip_svc] ... " $stat


###### Check IP SAU (ifconfig)

stat="NOK"
ifconfig | grep $ip_sau >/dev/null 2>&1
[[ $? -eq 0 ]] && stat="OK"
printf "%-45s %25s %-50s\n" "### Check IP SAU (ifconfig)" "[$ip_sau] ... " $stat


###### Check IP ADM (ifconfig)

stat="NOK"
ifconfig | grep $ip_adm >/dev/null 2>&1
[[ $? -eq 0 ]] && stat="OK"
printf "%-45s %25s %-50s\n" "### Check IP ADM (ifconfig)" "[$ip_adm] ... " $stat


###### Check IP NAS (ifconfig)

if [ $ip_nas != "-" ]; then
  stat="NOK"
  ifconfig | grep $ip_nas >/dev/null 2>&1
  [[ $? -eq 0 ]] && stat="OK"
  printf "%-45s %25s %-50s\n" "### Check IP NAS (ifconfig)" "[$ip_nas] ... " $stat
else   
  printf "%-50s %20s\n" "### Check IP NAS (ifconfig)" "[$ip_nas] "
fi


###### Check IP SVC dans /etc/hosts

stat="NOK"
cat /etc/hosts | grep -v "^#" | grep $ip_svc | grep -i -e $DOMAIN1 -e $DOMAIN2 | grep -i "$h" | grep -v -i "$h-a" | grep -v -i "$h-s" >/dev/null 2>&1
[[ $? -eq 0 ]] && stat="OK"
printf "%-45s %25s %-50s\n" "### Check IP SVC dans /etc/hosts" "[$ip_svc] ... " $stat


###### Check IP SAU dans /etc/hosts

stat="NOK"
cat /etc/hosts | grep -v "^#" | grep $ip_sau | grep -i -e $DOMAIN1 -e $DOMAIN2 | grep -i "$h-s" | grep -v -i "$h-a" >/dev/null 2>&1
[[ $? -eq 0 ]] && stat="OK"
printf "%-45s %25s %-50s\n" "### Check IP SAU dans /etc/hosts" "[$ip_sau] ... " $stat


###### Check IP ADM dans /etc/hosts

stat="NOK"
cat /etc/hosts | grep -v "^#" | grep $ip_adm | grep -i -e $DOMAIN1 -e $DOMAIN2 | grep -i "$h-a" | grep -v -i "$h-s" >/dev/null 2>&1
[[ $? -eq 0 ]] && stat="OK"
printf "%-45s %25s %-50s\n" "### Check IP ADM dans /etc/hosts" "[$ip_adm] ... " $stat


###### Check IP NAS dans /etc/hosts

if [ $ip_nas != "-" ]; then
  stat="NOK"
  cat /etc/hosts | grep -v "^#" | grep $ip_nas | grep -i "$h-sil" >/dev/null 2>&1
  [[ $? -eq 0 ]] && stat="OK"
  printf "%-45s %25s %-50s\n" "### Check IP NAS dans /etc/hosts" "[$ip_nas] ... " $stat
else
  printf "%-50s %20s\n" "### Check IP NAS dans /etc/hosts" "[$ip_nas] "
fi


###### Check IP SVC dans DNS

stat="NOK"
dns=$(nslookup $h | tail -n +4 | grep -i Address | awk -F' ' '{print $2}')
[[ $dns == $ip_svc ]] && stat="OK"
nb=$(nslookup $h | tail -n +4 | grep -i Address | wc -l)
[[ $nb -gt 1 ]] && stat="NOK (+ d'une entree dans le DNS)"
printf "%-45s %25s %-50s\n" "### Check IP SVC dans DNS" "[$ip_svc] ... " $stat


###### Check IP SAU dans DNS

stat="NOK"
dns=$(nslookup $h-s | tail -n +4 | grep -i Address | awk -F' ' '{print $2}')
[[ $dns == $ip_sau ]] && stat="OK"
nb=$(nslookup $h-s | tail -n +4 | grep -i Address | wc -l)
[[ $nb -gt 1 ]] && stat="NOK (+ d'une entree dans le DNS)"
printf "%-45s %25s %-50s\n" "### Check IP SAU dans DNS" "[$ip_sau] ... " $stat


###### Check IP ADM dans DNS

stat="NOK"
dns=$(nslookup $h-a | tail -n +4 | grep -i Address | awk -F' ' '{print $2}')
[[ $dns == $ip_adm ]] && stat="OK"
nb=$(nslookup $h-a | tail -n +4 | grep -i Address | wc -l)
[[ $nb -gt 1 ]] && stat="NOK (+ d'une entree dans le DNS)"
printf "%-45s %25s %-50s\n" "### Check IP ADM dans DNS" "[$ip_adm] ... " $stat


###### Check IP NAS dans DNS

if [ $ip_nas != "-" ]; then
  stat="NOK"
  dns=$(nslookup $h-sil | tail -n +4 | grep -i Address | awk -F' ' '{print $2}')
  [[ $dns == $ip_nas ]] && stat="OK"
  nb=$(nslookup $ip_nas | tail -n +4 | grep -i Address | wc -l)
  [[ $nb -gt 1 ]] && stat="NOK (+ d'une entree dans le DNS)"
  printf "%-45s %25s %-50s\n" "### Check IP NAS dans DNS" "[$ip_nas] ... " $stat
else
  printf "%-50s %20s\n" "### Check IP NAS dans DNS" "[$ip_nas] "
fi


###### Check resolv.conf (search)

stat="NOK"
cat /etc/resolv.conf | grep search | grep tethys.int | grep marium.int >/dev/null 2>&1
[[ $? -eq 0 ]] && stat="OK"
printf "%-50s %20s %-50s\n" "### Check resolv.conf (search)" " ... " $stat


###### Check resolv.conf (nameserver)

stat="NOK"
res=$(cat /etc/resolv.conf | grep nameserver | wc -l 2>&1)
[[ $res -eq 2 ]] && stat="OK"
printf "%-50s %20s %-50s\n" "### Check resolv.conf (nameserver)" " ... " $stat


###### check site DNS

for i in $(cat /etc/resolv.conf | grep nameserver | awk -F' ' '{print $2}'); do
  res=$(nslookup $i | grep -i 'name' | awk -F' ' '{print $4}')
  stat="NOK ($res incorrecte pour le site $site)" 
  index=0
  echo $res | grep -i "^[a-z]" >/dev/null 2>&1
  if [ $? -eq 0 ]; then
     for serv in "${SERV_DNS[@]}"; do
    echo $res | grep -i $serv >/dev/null 2>&1
    if [ $? -eq 0 ]; then
       echo $site | grep -i ${SITE_DNS[index]} >/dev/null 2>&1
           [[ $? -eq 0 ]] && stat="OK"
       break
    fi   
    ((index++))
     done
   else
     for serv in "${IP_DNS[@]}"; do
    echo $res | grep -i $serv >/dev/null 2>&1
    if [ $? -eq 0 ]; then
       echo $site | grep -i ${SITE_DNS[index]} >/dev/null 2>&1
           [[ $? -eq 0 ]] && stat="OK"
       break
    fi   
    ((index++))
     done
  fi
  printf "%-40s %30s %-50s\n" "### check site DNS $i" "[$res] ... " $stat
done


###### check nslookup DNS

for i in $(cat /etc/resolv.conf | grep nameserver | awk -F' ' '{print $2}'); do
  stat="NOK"
  res=$(nslookup $i | grep -i 'name' | awk -F' ' '{print $4}')
  nslookup $i >/dev/null 2>&1
  [[ $? -eq 0 ]] && stat="OK"
  printf "%-40s %30s %-50s\n" "### check nslookup DNS $i" "[$res] ... " $stat
done


###### Check NTP

stat="NOK"
ntpstat >/dev/null 2>&1
[[ $? -eq 0 ]] && stat="OK"
printf "%-40s %30s %-50s\n" "### Check NTP" " ... " $stat


####### Check .ssh/authorized_keys 

stat="OK"
checkpubkeys=" cat /root/.ssh/authorized_keys | grep -i"
checkpubkeysinvalides="$checkpubkeys -v"
checkpubkeystotal=" cat /root/.ssh/authorized_keys | grep '^ssh' | wc -l"
for user in "${PUBKEYS[@]}"; do
  checkpubkeys="$checkpubkeys -e '$user'"
  checkpubkeysinvalides="$checkpubkeysinvalides -e '$user'"
done
checkpubkeys="$checkpubkeys | wc -l"
checkpubkeysinvalides="$checkpubkeysinvalides"
nbpubkeys=`eval ${checkpubkeys}`
nbpubkeystotal=`eval ${checkpubkeystotal}`
miss=$(expr $NB_PUBKEYS - $nbpubkeys)
res=$(expr $nbpubkeystotal - $nbpubkeys)
echo $env | grep -i "production" >/dev/null # Si c'est un serveur de préprod ou prod alors on met en Warning.
horsprod=$?
if [ $horsprod -eq 1 ]; then
   [[ $res -ne 0 ]] || [[ $miss -ne 0 ]] && stat="WARN ($res entree(s) non valide(s) et $miss entree(s) manquante(s))"
   reskeys=`eval ${checkpubkeysinvalides} | sed 's/^/WARN - /g'`
else
   [[ $res -ne 0 ]] || [[ $miss -ne 0 ]] && stat="NOK ($res entree(s) non valide(s) et $miss entree(s) manquante(s))"
   reskeys=`eval ${checkpubkeysinvalides} | sed 's/^/NOK - /g'`
fi

printf "%-50s %20s %-50s\n" "### Check fichier .ssh/authorized_keys" " ... " $stat
printf '%s\n' "$reskeys"


####### Check /srce dans auto.direct 

stat="WARN"
grep "/srce" /etc/auto.direct >/dev/null 2>&1
[[ $? -eq 0 ]] && stat="OK"
printf "%-50s %20s %-50s\n" "### Check /srce dans auto.direct" " ... " $stat


####### Check montage /srce 

stat=$WARN
# Ajout cd /srce pour valider l'automontage
cd /srce && df -Ph | grep "/srce" >/dev/null 2>&1
[[ $? -eq 0 ]] && stat="OK" && srce_mounted=1
printf "%-50s %20s %-50s\n" "### Check montage /srce" " ... " $stat


####### Check durcissement

if [ $durci -eq 1 ]; then
stat="NOK"
  if [ $srce_mounted -eq 1 ]; then
     list_ko_durci_result=$(${PATH_TO_DURCISSEMENT_SCRIPT}/lanceur.bash check | grep KO)
     list_ko_durci_return_code=$?
     [[ $list_ko_durci_return_code -ne 0 ]] && stat="OK"  # S'il n'y a pas de KO grepés, c'est que le check est OK / Attention, si le lanceur plante (et que du coup on ne grep pas de KO, on n'aura OK ce qui peut fausser la donne) 
     printf "%-50s %20s %-50s\n" "### Check durcissement" " ... " $stat
     [[ $list_ko_durci_return_code -eq 0 ]] && echo "$list_ko_durci_result" | sed 's/\x1B\[[0-9;]\+[A-Za-z]//g' | sed 's/^/NOK - /g'  # Supprimer les caractères pour la couleur que renvoie le script + afficher les règles KO
  else
     printf "%-50s %20s %-50s\n" "### Check durcissement impossible" " ... " "WARN (car srce non monte)"
  fi
else
  printf "%-50s %20s %-50s\n" "### Check durcissement" " ... " "WARN (Pas de check car OS non durci)"
fi


####### Check /etc/sudoers

declare -a tableau_des_sudoers=()
declare -a tableau_des_sudoers_et_droits=()
stat="NOK"
i=0
for user in $(cat /etc/passwd | grep -e '/bin/' | grep -v -e root -e sync | awk -F':' '{ print $1}'); do
  nb=$(cat /etc/sudoers | grep -n $user | wc -l)
  [[ $nb -ne 0 ]] && tableau_des_sudoers=( "${tableau_des_sudoers[@]}" "$user" ) # Pour afficher les sudoers en trop
  [[ $nb -ne 0 ]] && tableau_des_sudoers_et_droits=( "${tableau_des_sudoers_et_droits[@]}" "$(cat /etc/sudoers | grep $user | sed 's/^/NOK - /g')" ) # Pour afficher les sudoers en trop
  ((i+=$nb))
done
[[ $i -eq 0 ]] && stat="OK"

if [ ${#tableau_des_sudoers[@]} -ne 0 ]; then
    echo $env | grep -i "production" >/dev/null # Si c'est un serveur de préprod ou prod alors on met en Warning.
    horsprod=$?
    if [ $horsprod -eq 1 ]; then
        stat="WARN (Vérifier si les users suivants devraient se trouver dans le sudoers et s'ils ont les bons droits : ${tableau_des_sudoers[@]})"
    else
        stat="NOK (Vérifier si les users suivants devraient se trouver dans le sudoers et s'ils ont les bons droits : ${tableau_des_sudoers[@]})"
    fi
fi
printf "%-50s %20s %-50s\n" "### Check /etc/sudoers" " ... " $stat

if [ ${#tableau_des_sudoers[@]} -ne 0 ]; then
    printf '%s\n' "${tableau_des_sudoers_et_droits[@]}"
fi


####### Check si sauvegarde NB successful

nb_save=$(cat $OPSCENTER_FILES | grep -i $h | grep -n -i 'Successful' | grep -v 'Archived Redo Log Backup' | wc -l)
if [ $nb_save -ne 0 ]; then
        stat="OK (Sauvegardes de moins de 24h trouvées dans OPSCENTER : $nb_save)"
    else
        echo $env | grep -i "production" >/dev/null # Si c'est un serveur de préprod ou prod alors on met en Warning.
        horsprod=$?
        if [ $horsprod -eq 1 ]; then
            stat="WARN (Aucune sauvegarde trouvée dans OPSCENTER dans les dernières 24h)"
        else
            stat="NOK (Aucune sauvegarde trouvée dans OPSCENTER dans les dernières 24h)"
        fi
fi

printf "%-50s %20s %-50s\n" "### Check si sauvegarde NB successful" "... " $stat


###### Check FS et volumétries

list=()
list[0]="" && nb=0

entete_once=0
for i in $(df -PBM | grep -v -i -e '/srce' -e '/shm' -e 'Filesystem'); do
  stat="  WARN (différence de taille supérieure de $SIZE_PERCENT%)"
  distant=$(echo $i | awk -F' ' '{print $6" "$2}')
  size_distant=$(echo $distant | awk -F' ' '{print $2}' | sed 's/[^0-9]*//g')
  vg=$(echo $i | awk -F' ' '{print $1}' | awk -F'/' '{print $4}' | awk -F'-' '{print $1}')
  [[ $vg == "" ]] && vg="Partition"
  mount=$(echo $i | awk -F' ' '{print $6}')
  mount="${mount} "
  local=$(cat $RECETTE_REMOTE_REP/$h-FS.csv | grep "^$mount" | awk -F' ' '{print $2}' | sed "s/\"//g" | sed "s/,/./g")
  [[ $vg == "" ]] && vg="-"
  [[ $local == "" ]] && local="-"
  [[ $distant == "" ]] && distant="-"
  if [ "$local" != "-" ]; then
    size_local_tmp=$(echo $local | sed 's/[^0-9.]*//g')
    echo "$size_local_tmp" | grep '\.' >/dev/null 2>&1
    is_real=$?
    [[ $is_real -ne 0 ]] && size_local=$size_local_tmp".0" || size_local=$size_local_tmp 
    size_local_int=$(echo $size_local | awk -F'.' '{print $1}')
    size_local_dec=$(echo $size_local | awk -F'.' '{print $2}')
    [[ $size_local_int -eq 0 ]] && size_local=$(expr $size_local_dec \* 1024 / 10) || size_local=$(expr $size_local_int \* 1024 + $size_local_dec \* 1024 / 10) 
    size_local_percent_tolerate=$(expr $size_local / $SIZE_PERCENT)
    size_local_plus_tolerate=$(expr $size_local + $size_local_percent_tolerate)
    size_local_minus_tolerate=$(expr $size_local - $size_local_percent_tolerate)
    [[ $size_local_minus_tolerate -ge $size_distant ]] && stat="  NOK (Taille FS égale ou inférieur d'au moins $SIZE_PERCENT% à la norme)"
    [[ $size_local_plus_tolerate -le $size_distant  ]] && stat="  WARN (Taille FS égale ou supérieure d'au moins $SIZE_PERCENT% à la norme)"
    [[ $size_distant -ge $size_local_minus_tolerate && $size_distant -le $size_local_plus_tolerate ]] && stat="  OK"
  else
     #stat="NOK (Ce FS n'existe pas dans le DIT)"
     stat="Ce FS n'est pas controllé par la recette systeme"
  fi
  
  [[ "$stat" != "  OK" ]]
  if [ $entete_once -eq 0 ]; then
    printf "%-50s %20s\n" "### Check FS (tolérance de +/- $SIZE_PERCENT%):"
    printf "\n%-20s %45s %45s %50s\n" "VG" "SERVEUR" "NORME (Go)" "RESULTAT"
    entete_once=1
  fi
  printf "%-20s %45s %45s %50s\n" $vg $distant "[$local]" $stat
  
  list[$nb]=$mount
  ((nb+=1))
done
checkfsabsents="cat $RECETTE_REMOTE_REP/$h-FS.csv | grep -v -i -e 'vg' -e '/srce' -e '/shm' -e 'Filesystem' -e ' 0 ' -e ' 0.0 ' -e ' 0,0 '"
i=0

while [ $i -le $((nb-1)) ]
do
  checkfsabsents="$checkfsabsents -e '${list[$i]}'"
  ((i+=1))
done
for i in `eval ${checkfsabsents}`; do
  printf "%-20s %45s %45s %50s\n" "-" "-" $i "  NOK (Ce FS n'existe pas sur le serveur)"
done
printf "\n"
echo
done


###### Nettoyage sur serveur distant
rm -rf $RECETTE_REMOTE_REP >/dev/null 2>&1  # Nettoyage -> Suppression de tout le répertoire recette
