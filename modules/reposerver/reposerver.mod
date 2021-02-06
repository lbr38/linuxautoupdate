#!/bin/bash
# Module reposerver
# Module permettant de se ratacher à un serveur de repo exécutant repomanager 


loadModule() {
# Vérification de la présence du fichier de conf
if [ ! -f "${MODULES_DIR}/reposerver/reposerver.conf" ];then
	echo -e "[${ROUGE} ERREUR ${RESET}] Le fichier de conf du module reposerver est introuvable"
	clean_exit
else
	MOD_CONF="${MODULES_DIR}/reposerver/reposerver.conf"
fi

# Récupération du nom du module :
MOD_NAME=$(grep "^NAME=" "${MODULES_DIR}/reposerver/reposerver.conf" | cut -d'=' -f2 | sed 's/"//g')

# Vérification de l'activation de ce module :
MOD_ENABLED=$(grep "^ENABLED=" "${MODULES_DIR}/reposerver/reposerver.conf" | cut -d'=' -f2 | sed 's/"//g')
if [ "$MOD_ENABLED" == "yes" ];then
	echo -e " - Module reposerver : ${JAUNE}Activé${RESET}"
else
	echo -e " - Module reposerver : ${JAUNE}Désactivé${RESET}"
fi

return 0
}


#### FONCTIONS ####

# Récupération de la configuration complète du module, dans son fichier de conf
getModConf() {
REPOSERVER_URL="$(grep "^URL=" $MOD_CONF | cut -d'=' -f2 | sed 's/"//g')"
REPOSERVER_OS_FAMILY="$(grep "^OS_FAMILY=" $MOD_CONF | cut -d'=' -f2 | sed 's/"//g')"
REPOSERVER_OS_NAME="$(grep "^OS_NAME=" $MOD_CONF | cut -d'=' -f2 | sed 's/"//g')"
REPOSERVER_OS_VERSION="$(grep "^OS_VERSION=" $MOD_CONF | cut -d'=' -f2 | sed 's/"//g')"
REPOSERVER_MANAGE_CLIENTS_CONF="$(grep "^MANAGE_CLIENTS_CONF=" $MOD_CONF | cut -d'=' -f2 | sed 's/"//g')"
REPOSERVER_MANAGE_CLIENTS_REPOSCONF="$(grep "^MANAGE_CLIENTS_REPOSCONF=" $MOD_CONF | cut -d'=' -f2 | sed 's/"//g')"

if [ -z "$REPOSERVER_URL" ];then
	echo -e " - Module reposerver : [${ROUGE} ERREUR ${RESET}] URL du serveur de repo inconnue"
	return 1
fi
}

updateModConf() {
# On re-télécharge la conf complète du serveur de repo afin de la mettre à jour dans le fichier de conf
GET_CONF=$(curl -s "${REPOSERVER_URL}/${REPOSERVER_URL}.conf")
if [ -z "$GET_CONF" ];then
	echo -e "erreur, la conf récupérée est vide"
	return 1
fi

# On recrée le fichier de conf
# Sauvegarde de la partie [MODULE]
sed -n -e '/\[MODULE\]/,/^$/p' $MOD_CONF > /tmp/linuxautoupdate_mod_reposerver.tmp

# Ajout de la nouvelle conf [REPOSERVER]
echo "[REPOSERVER]" >> /tmp/linuxautoupdate_mod_reposerver.tmp
echo -e "$GET_CONF" >> /tmp/linuxautoupdate_mod_reposerver.tmp

# On remplace alors le fichier de conf actuel par le nouveau
cat /tmp/linuxautoupdate_mod_reposerver.tmp > $MOD_CONF

# Puis on recharge à nouveau les paramètres
getModConf
}


preCheck() {
# Si REPOSERVER_OS_FAMILY, *NAME ou *VERSION diffère du type de serveur sur lequel est exécuté ce module (par exemple le serveur reposerver est un serveur CentOS et nous somme sur un serveur Debian), alors on affiche un warning
if [ "$REPOSERVER_OS_FAMILY" != "$OS_FAMILY" ];then
	echo "erreur os family différent"
	return 1
fi
if [ "$REPOSERVER_OS_NAME" != "$OS_NAME" ];then
	echo "erreur os name différent"
	return 1
fi
if [ "$REPOSERVER_OS_VERSION" != "$OS_VERSION" ];then
	echo "erreur os version différent"
	return 1
fi
}


updateConfFile() {
# Si le serveur reposerver ne gère pas les profils ou que le client refuse d'être mis à jour par son serveur de repo, on quitte la fonction
if [ "$REPOSERVER_MANAGE_CLIENTS_CONF" == "no" ] || [ "$ALLOW_CONF_UPDATE" == "no" ];then
	return 1
fi

# Sinon, on récupère la conf auprès du serveur de repo, TYPE étant le nom de profil
GET_CONF=$(curl -s "${REPOSERVER_URL}/${SERVER_TYPE}/config")
if [ -z "$GET_CONF" ];then
	echo -e " → Mise à jour du fichier de conf :\t[$ROUGE ERREUR $RESET] pendant la récupération du fichier de configuration depuis ${REPOSERVER_URL}"
	return 1
fi

# On applique le nouveau fichier de conf téléchargé
# D'abord on nettoie la partie [SOFT] du fichier de conf car c'est cette partie qui va être remplacée par la nouvelle conf : 
sed -i '/^\[SOFT\]/,$d' "$CONF" &&

# Puis on réinjecte avec la nouvelle conf téléchargée :
echo -e "[SOFT]\n${GET_CONF}" >> "$CONF"

# Enfin on applique la nouvelle conf en récupérant de nouveau les paramètres du fichier de conf :
getConf
}


updateReposConfFiles() { # Mets à jour les fichiers de conf .repo en allant les récupérer sur le serveur de repo
# Si on est autorisé à mettre à jour les fichiers de conf de repos et si le serveur de repos le gère
if [ "$REPOSERVER_MANAGE_CLIENTS_REPOSCONF" == "yes" ] && [ "$CONF_ALLOW_REPOSFILES_OVERWRITE" == "yes" ];then
	echo -ne "Mise à jour de la configuration des repos : "

	# Création d'un répertoire temporaire pour télécharger les fichiers .repo
	rm -rf /tmp/linuxautoupdate/reposconf/ &&
	mkdir -p /tmp/linuxautoupdate/reposconf/ && 
	cd /tmp/linuxautoupdate/reposconf/ &&

	# Récupération des fichiers depuis le serveur de repo
	if [ "$OS_FAMILY" == "Redhat" ];then
		wget -q -r -np -nH --cut-dirs=2 -R index.html "https://${REPOSERVER_URL}/${SERVER_TYPE}/*.repo"
		RESULT=$?
	fi
	if [ "$OS_FAMILY" == "Debian" ];then
		wget -q -r -np -nH --cut-dirs=2 -R index.html "https://${REPOSERVER_URL}/${SERVER_TYPE}/*.list"
		RESULT=$?
	fi

	if [ "$RESULT" -ne "0" ];then
		echo -e "[$ROUGE ERREUR $RESET] lors du téléchargement des fichiers de conf .repo depuis HOST-REPOSERVER"
		return 1
	fi

	if [ "$OS_FAMILY" == "Redhat" ];then
		# On remplace dedans les occurences __ENV__ par $SERVER_ENV
		sed -i "s|__ENV__|${SERVER_ENV}|g" *.repo &&
		# On crée le répertoire servant à backuper les anciens fichiers .repo
		cd /etc/yum.repos.d/ &&
		mkdir -p backups/ &&
		# Puis on crée un backup archive à la date du jour
		tar czf backup_yum.repos.d_${DATE_AMJ}.tar.gz *.repo &&
		# Qu'on déplace ensuite dans le dossier backups
		mv backup_yum.repos.d_${DATE_AMJ}.tar.gz backups/ &&
		# Suppression des fichiers .repo actuels, qui vont être remplacés par les nouveaux
		rm /etc/yum.repos.d/*.repo -f &&
		# Déplacement des nouveaux fichiers de conf dans /etc/yum.repos.d/
		mv /tmp/linuxautoupdate/reposconf/*.repo /etc/yum.repos.d/ &&
		# Application des droits sur les nouveaux fichiers .repo
		chown root:root /etc/yum.repos.d/*.repo && chmod 660 /etc/yum.repos.d/*.repo &&
		# Vidage du cache yum
		yum clean all -q && 
		echo -e "[$VERT OK $RESET]"
	fi

	if [ "$OS_FAMILY" == "Debian" ];then
		# On remplace dedans les occurences __ENV__ par $SERVER_ENV
		sed -i "s|__ENV__|${SERVER_ENV}|g" *.list &&
		# On crée le répertoire servant à backuper les anciens fichiers .list
		cd /etc/apt/sources.list.d/ &&
		mkdir -p backups/ &&
		# Puis on crée un backup archive à la date du jour
		tar czf backup_apt.sourceslist.d_${DATE_AMJ}.tar.gz *.list &&
		# Qu'on déplace ensuite dans le dossier backups
		mv backup_apt.sourceslist.d_${DATE_AMJ}.tar.gz backups/ &&
		# Suppression des fichiers .list actuels, qui vont être remplacés par les nouveaux
		rm /etc/apt/sources.list.d/*.list -f &&
		# Déplacement des nouveaux fichiers de conf dans /etc/apt/sources.list.d/
		mv /tmp/linuxautoupdate/reposconf/*.list /etc/apt/sources.list.d/ &&
		# Application des droits sur les nouveaux fichiers .list
		chown root:root /etc/apt/sources.list.d/*.list && chmod 660 /etc/apt/sources.list.d/*.list &&
		# Vidage du cache apt
		apt clean && 
		echo -e "[$VERT OK $RESET]"
	fi
else
	if [ "$REPOSERVER_MANAGE_CLIENTS_REPOSCONF" != "yes" ];then
		echo -e "${JAUNE}Paramètre REPOSERVER_MANAGE_CLIENTS_REPOSCONF=\"no\" ou est vide; Rien n'est fait, la configuration des fichiers de repos reste inchangée$RESET"
	fi

	if [ "$CONF_ALLOW_REPOSFILES_OVERWRITE" != "yes" ];then
		echo -e "${JAUNE}Paramètre ALLOW_REPOSFILES_OVERWRITE=\"no\" ou est vide; Rien n'est fait, la configuration des fichiers de repos reste inchangée$RESET"
	fi
fi
echo ""
}

main () {
# On récupère la configuration du module, en l'occurence la configuration du serveur de repo
getModConf

# On met à jour la configuration du serveur de repo distant en lui demandant de renvoyer sa conf
updateModConf

# On vérifie que la configuration du serveur de repo est compatible avec notre OS
preCheck

# On met à jour notre configuration à partir du serveur de repo (profils), si cela est autorisé des deux côtés
updateConfFile

# On met à jour notre configuration des repos à partir du serveurs de repo (profils), si cela est autorisé des deux côtés
updateReposConfFiles
}