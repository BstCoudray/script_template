#!/bin/bash
FLAG=0
. ./config.sh
while read line
do
        if [ $FLAG -eq 0 ]
        then
                # Condition permettant de se debarasser de la premiere ligne
                FLAG=1
        else
                # Recuperation des variables du fichier CSV
                ID=$(echo $line | cut -d',' -f1 | tr -d '"')
                PRENOM=$(echo $line | cut -d'"' -f4)
                NOM=$(echo $line | cut -d'"' -f6)
                EMAIL=$(echo $line | cut -d'"' -f8)
                ADMIN=$(echo $line | cut -d'"' -f10)
                # Test si l'utilisateur existe deja
                NBC=$(ldapsearch -x -LLL -b ${DOMAIN_COMPONENT} uid=${ID} | wc -l)
                if [ $NBC -eq 0 ]
                then
                        #### Il n'existe pas, il faut le creer ####
                        # Recuperation de l'ID libre suivant
                        CURRENT_ID=$(cat ${ID_FILE})
                        # Clone du template user.ldif
                        DEST_FILE=tempuser.ldif
                        cp templates/user.ldiftemplate ${DEST_FILE}
                        # Injection des variables dans le template
                        sed -i "s|<##USER_LOGIN##>|${ID}|g" ${DEST_FILE}
                        sed -i "s|<##CLIENT_NAME##>|${CLIENT_NAME}|g" ${DEST_FILE}
                        sed -i "s|<##PRENOM##>|${PRENOM}|g" ${DEST_FILE}
                        sed -i "s|<##NOM##>|${NOM}|g" ${DEST_FILE}
                        sed -i "s|<##EMAIL##>|${EMAIL}|g" ${DEST_FILE}
                        sed -i "s|<##USER_UID##>|${CURRENT_ID}|g" ${DEST_FILE}
                        sed -i "s|<##DOMAIN_COMPONENT##>|${DOMAIN_COMPONENT}|g" ${DEST_FILE}
                        # Incrementation de l'ID utilisateur
                        CURRENT_ID=$(( $CURRENT_ID + 1 ))
                        echo $CURRENT_ID > ${ID_FILE}
                        # Integration du user dans l'annuaire
                        ldapadd -x -D "cn=admin,${DOMAIN_COMPONENT}" -w ${DOMAIN_PASSWORD} -f ${DEST_FILE}
                        # Suppression du fichier temporaire
                        rm ${DEST_FILE}
                else
                        #### Il existe, il faut le verifier ####
                        echo "L'utilisateur ${ID} existe deja";
                        USER_PRENOM=$(ldapsearch -x -LLL -b ${DOMAIN_COMPONENT} "uid=${ID}" | grep "cn:" | cut -d" " -f2)
                        USER_NOM=$(ldapsearch -x -LLL -b ${DOMAIN_COMPONENT} "uid=${ID}" | grep "sn:" | cut -d" " -f2)
                        USER_MAIL=$(ldapsearch -x -LLL -b ${DOMAIN_COMPONENT} "uid=${ID}" | grep "mail:" | cut -d" " -f2)
                        USER_DN=$(ldapsearch -x -LLL -b ${DOMAIN_COMPONENT} "uid=${ID}" |grep "dn:" | cut -d" " -f2)
                        if [ "$USER_PRENOM" != "$PRENOM" ]
                        then
                                echo "User ${ID} is not conform"
                                cp templates/update.ldiftemplate tempupdate.ldif
                                sed -i "s|<##OBJECT_DN##>|$USER_DN|g" tempupdate.ldif
                                sed -i "s|<##PROPERTY##>|cn|g" tempupdate.ldif
                                sed -i "s|<##VALUE##>|$PRENOM|g" tempupdate.ldif
                                ldapmodify -x -D cn=admin,${DOMAIN_COMPONENT} -w $DOMAIN_PASSWORD -f tempupdate.ldif
                                rm tempupdate.ldif
                        fi
                        if [ "$USER_NOM" != "$NOM" ]
                        then
                                echo "User ${ID} is not conform"
                                cp templates/update.ldiftemplate tempupdate.ldif
                                sed -i "s|<##OBJECT_DN##>|$USER_DN|g" tempupdate.ldif
                                sed -i "s|<##PROPERTY##>|sn|g" tempupdate.ldif
                                sed -i "s|<##VALUE##>|$NOM|g" tempupdate.ldif
                                ldapmodify -x -D cn=admin,${DOMAIN_COMPONENT} -w $DOMAIN_PASSWORD -f tempupdate.ldif
                                rm tempupdate.ldif
                        fi
                        if [ "$USER_MAIL" != "$EMAIL" ]
                        then
                                echo "User ${ID} is not conform"
                                cp templates/update.ldiftemplate tempupdate.ldif
                                sed -i "s|<##OBJECT_DN##>|$USER_DN|g" tempupdate.ldif
                                sed -i "s|<##PROPERTY##>|mail|g" tempupdate.ldif
                                sed -i "s|<##VALUE##>|$EMAIL|g" tempupdate.ldif
                                ldapmodify -x -D cn=admin,${DOMAIN_COMPONENT} -w $DOMAIN_PASSWORD -f tempupdate.ldif
                                rm tempupdate.ldif
                        fi
                fi
        fi
done < input.csv
cat input.csv | cut -d'"' -f2 | grep -vx "ID" > required_users
for userdn in $(ldapsearch -x -LLL -b ${DOMAIN_COMPONENT} | grep -v "cn=admind" | egrep "uid=|cn=" | cut -d" " -f2)
do
        user=$(echo $userdn | cut -d"=" -f2 | cut -d"," -f1)
        grep -x $user required_users > /dev/null 2>&1
        if [ $? -ne 0 ]
        then
                echo -n "deleting entry $userdn..."
                ldapdelete -x -D cn=admin,${DOMAIN_COMPONENT} -w ${DOMAIN_PASSWORD} $userdn
                echo "[OK]"
        fi
done
rm required_users
echo;
echo -n "Checking if ldap database is conform..."
CSV_HASH=$(cat input.csv | cut -d'"' -f2 | grep -vx "ID" | sort | md5sum)
LDAP_HASH=$(ldapsearch -x -LLL -b ${DOMAIN_COMPONENT} | grep "uid=" | cut -d"=" -f2 | cut -d"," -f1 | sort | md5sum)
if [ "$CSV_HASH" == "$LDAP_HASH" ]
then
        echo "[OK]"
else
        echo "[FAILED]"
        echo "Administrator intervention is required."
fi
exit;