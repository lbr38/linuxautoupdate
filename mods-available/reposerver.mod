#!/bin/bash
# Module reposerver
# Module permettant de se ratacher à un serveur de repo exécutant repomanager 

MOD_CONF="${MODULES_CONF_DIR}/reposerver.conf"

#### FONCTIONS ####

# Installation du module
install() {
	cd ${MODULES_ENABLED_DIR}/ &&
	ln -sfn ../mods-available/${MODULE}.mod 00_reposerver.mod &&
	mkdir -p "${MODULES_CONF_DIR}" &&
	\cp "${TMP_DIR}/mods-available/configurations/${MODULE}.conf" ${MODULES_CONF_DIR}/ &&
	echo -e "Installation du module ${JAUNE}reposerver${RESET} : [$VERT OK $RESET]"
	configure
}


configure() {
	# Configuration du module reposerver.mod (fichier de configuration reposerver.conf)
	REPOSERVER_URL=""
	while [ -z "$REPOSERVER_URL" ];do
		echo -ne " → Adresse du serveur Repomanager : https://"; read -p "" REPOSERVER_URL
	done
	REPOSERVER_URL="https://${REPOSERVER_URL}"

	echo -ne " → Niveau de Fail-level à attribuer à ce module [1-3] : "; read -p "" FAILLEVEL
	if [ -z "$FAILLEVEL" ];then FAILLEVEL="3";fi

	echo -e "[MODULE]" > $MOD_CONF
	echo -e "FAILLEVEL=\"$FAILLEVEL\"" >> $MOD_CONF
	echo -e "\n[REPOSERVER]" >> $MOD_CONF
	echo -e "URL=\"${REPOSERVER_URL}\"" >> $MOD_CONF

	# Configuration de linuxautoupdate (fichier de configuration linuxautoupdate.conf)
	# Ajout des paramètres si n'existe pas
	if ! grep -q "^REPOSERVER_ALLOW_AUTOUPDATE" "$CONF";then
		echo -ne " → Autoriser le serveur ${JAUNE}${REPOSERVER_URL}${RESET} à mettre à jour la configuration de linuxautoupdate (yes/no) : "; read -p "" CONFIRM
		if [ "$CONFIRM" == "yes" ] || [ "$CONFIRM" == "y" ];then
			echo "REPOSERVER_ALLOW_AUTOUPDATE=\"yes\"" >> "$CONF"
		fi
	fi
	if ! grep -q "^REPOSERVER_ALLOW_REPOSFILES_UPDATE" "$CONF";then
		echo -ne " → Autoriser le serveur ${JAUNE}${REPOSERVER_URL}${RESET} à mettre à jour la configuration des repos sur cette machine (yes/no) : "; read -p "" CONFIRM
		if [ "$CONFIRM" == "yes" ] || [ "$CONFIRM" == "y" ];then
			echo "REPOSERVER_ALLOW_REPOSFILES_UPDATE=\"yes\"" >> "$CONF"
		fi
	fi
	if ! grep -q "^REPOSERVER_ALLOW_OVERWRITE" "$CONF";then
		echo -ne " → Autoriser le serveur ${JAUNE}${REPOSERVER_URL}${RESET} à forcer les deux paramètres précédents à ${JAUNE}yes${RESET} si ceux-ci sont paramétrés à ${JAUNE}no${RESET} (yes/no) : "; read -p "" CONFIRM
		if [ "$CONFIRM" == "yes" ] || [ "$CONFIRM" == "y" ];then
			echo "REPOSERVER_ALLOW_OVERWRITE=\"yes\"" >> "$CONF"
		fi
	fi
}


loadModule() {
	# Si le fichier de configuration du module est introuvable alors on le configure
	if [ ! -f "$MOD_CONF" ] || [ ! -s "$MOD_CONF" ];then
		configure
	fi
	# Idem, si l'URL du serveur de repo n'est pas renseignée alors on configure
	if [ -z $(grep "^URL=" $MOD_CONF | cut -d'=' -f2 | sed 's/"//g') ];then
		configure
	fi

	echo -e " - Module reposerver : ${JAUNE}Activé${RESET}"
}


# Récupération de la configuration complète du module, dans son fichier de conf
getModConf() {
	REPOSERVER_URL="$(grep "^URL=" $MOD_CONF | cut -d'=' -f2 | sed 's/"//g')"
	REPOSERVER_PROFILES_URL="$(grep "^PROFILES_URL=" $MOD_CONF | cut -d'=' -f2 | sed 's/"//g')"
	REPOSERVER_OS_FAMILY="$(grep "^OS_FAMILY=" $MOD_CONF | cut -d'=' -f2 | sed 's/"//g')"
	REPOSERVER_OS_NAME="$(grep "^OS_NAME=" $MOD_CONF | cut -d'=' -f2 | sed 's/"//g')"
	REPOSERVER_OS_VERSION="$(grep "^OS_VERSION=" $MOD_CONF | cut -d'=' -f2 | sed 's/"//g')"
	REPOSERVER_PACKAGES_OS_VERSION="$(grep "^PACKAGES_OS_VERSION=" $MOD_CONF | cut -d'=' -f2 | sed 's/"//g')"
	REPOSERVER_MANAGE_CLIENTS_CONF="$(grep "^MANAGE_CLIENTS_CONF=" $MOD_CONF | cut -d'=' -f2 | sed 's/"//g')"
	REPOSERVER_MANAGE_CLIENTS_REPOSCONF="$(grep "^MANAGE_CLIENTS_REPOSCONF=" $MOD_CONF | cut -d'=' -f2 | sed 's/"//g')"

	# Détection du FAILLEVEL pour ce module
	FAILLEVEL=$(grep "^FAILLEVEL=" "${MOD_CONF}" | cut -d'=' -f2 | sed 's/"//g')

	# Si on n'a pas pu récupérer le FAILLEVEL dans le fichier de conf alors on le set à 1 par défaut
	# De même si le FAILLEVEL récupéré n'est pas un chiffre alors on le set à 1
	if [ -z "$FAILLEVEL" ];then echo -e "[$JAUNE WARNING $RESET] Paramètre FAILLEVEL non configuré pour ce module → configuré à 1 (arrêt en cas d'erreur mineure ou critique)"; FAILLEVEL="1";fi
	if ! [[ "$FAILLEVEL" =~ ^[0-9]+$ ]];then echo -e "[$JAUNE WARNING $RESET] Paramètre FAILLEVEL non configuré pour ce module → configuré à 1 (arrêt en cas d'erreur mineure ou critique)"; FAILLEVEL="1";fi

	if [ -z "$REPOSERVER_URL" ];then
		echo -e " - Module reposerver : [${JAUNE} ERREUR ${RESET}] URL du serveur de repo inconnue ou vide"
		return 2
	fi

	# Si REPOSERVER_PACKAGES_OS_VERSION n'est pas vide, cela signifie que le serveur distant dispose de miroirs de paquets dont la version est différente de sa propre version
	# Dans ce cas on overwrite la variable OS_VERSION
	if [ ! -z "$REPOSERVER_PACKAGES_OS_VERSION" ];then REPOSERVER_OS_VERSION="$REPOSERVER_PACKAGES_OS_VERSION";fi

	return 0
}


updateModConf() {
	# On re-télécharge la conf complète du serveur de repo afin de la mettre à jour dans le fichier de conf
	GET_CONF=$(curl -s "${REPOSERVER_URL}/main.conf")
	if [ -z "$GET_CONF" ];then
		echo -e " [${JAUNE} ERREUR ${RESET}] La configuration du serveur de repo récupérée est vide"
		return 2
	fi

	# On recrée le fichier de conf
	# Sauvegarde de la partie [MODULE]
	sed -n -e '/\[MODULE\]/,/^$/p' $MOD_CONF > /tmp/linuxautoupdate_mod_reposerver.tmp

	# Ajout de la nouvelle conf [REPOSERVER]
	echo -e "$GET_CONF" >> /tmp/linuxautoupdate_mod_reposerver.tmp

	# On remplace alors le fichier de conf actuel par le nouveau
	cat /tmp/linuxautoupdate_mod_reposerver.tmp > $MOD_CONF

	# Puis on recharge à nouveau les paramètres
	getModConf
}


preCheck() {
	# Si l'url d'accès aux profils est inconnue alors on ne peut pas continuer
	if [ -z "$REPOSERVER_PROFILES_URL" ];then
		echo -e " [${JAUNE} ERREUR ${RESET}] L'URL d'accès aux profils est inconnue."
		return 1
	fi

	# Si REPOSERVER_OS_FAMILY, *NAME ou *VERSION diffère du type de serveur sur lequel est exécuté ce module (par exemple le serveur reposerver est un serveur CentOS et nous somme sur un serveur Debian), alors on affiche un warning
	if [ "$REPOSERVER_OS_FAMILY" != "$OS_FAMILY" ];then
		echo -e " [${JAUNE} ERREUR ${RESET}] Le serveur de repo distant ne gère pas la même famille d'OS que cette machine."
		return 2
	fi

	if [ "$REPOSERVER_OS_NAME" != "$OS_NAME" ];then
		echo -e " [${JAUNE} WARNING ${RESET}] Le serveur de repo distant ne gère pas le même OS que cette machine, les paquets peuvent être incompatibles."
		return 1
	fi

	if [ "$REPOSERVER_OS_VERSION" != "$OS_VERSION" ];then
		echo -e " [${JAUNE} ERREUR ${RESET}] Le serveur de repo distant ne gère pas la même version d'OS que cette machine."
		return 2
	fi
}


updateConfFile() {
	# Si le serveur reposerver ne gère pas les profils ou que le client refuse d'être mis à jour par son serveur de repo, on quitte la fonction
	if [ "$REPOSERVER_MANAGE_CLIENTS_CONF" == "no" ] || [ "$REPOSERVER_ALLOW_AUTOUPDATE" == "no" ];then
		if [ "$REPOSERVER_MANAGE_CLIENTS_CONF" == "no" ];then
			echo -e " → Mise à jour du fichier de conf :\t[$JAUNE ERREUR $RESET] Le serveur de repo ne gère pas la configuration des clients"
		fi
		if [ "$REPOSERVER_ALLOW_AUTOUPDATE" == "no" ];then
			echo -e " → Mise à jour du fichier de conf :\t[$JAUNE ERREUR $RESET] Mise à jour du fichier non autorisée par la configuration actuelle"
		fi

		return 1
	fi

	# Sinon, on récupère la conf auprès du serveur de repo, TYPE étant le nom de profil
	# 1er test pour voir la conf est récupérable (et qu'on ne choppe pas une 404 ou autre erreur)
	if ! curl -s "${REPOSERVER_PROFILES_URL}/${SERVER_TYPE}/config";then 
		echo -e " → Mise à jour du fichier de conf :\t[$JAUNE ERREUR $RESET] pendant la récupération du fichier de configuration depuis ${REPOSERVER_PROFILES_URL}"
		return 2
	fi

	# 2ème fois : cette fois on récupère la conf
	GET_CONF=$(curl -s "${REPOSERVER_PROFILES_URL}/${SERVER_TYPE}/config")
	if [ -z "$GET_CONF" ];then
		echo -e " → Mise à jour du fichier de conf :\t[$JAUNE ERREUR $RESET] pendant la récupération du fichier de configuration depuis ${REPOSERVER_PROFILES_URL}"
		return 2
	fi

	# On applique le nouveau fichier de conf téléchargé
	# D'abord on nettoie la partie [SOFT] du fichier de conf car c'est cette partie qui va être remplacée par la nouvelle conf : 
	sed -i '/^\[SOFTWARE CONFIGURATION\]/,$d' "$CONF" &&

	# Puis on réinjecte avec la nouvelle conf téléchargée :
	echo -e "[SOFTWARE CONFIGURATION]\n${GET_CONF}" >> "$CONF"

	# Enfin on applique la nouvelle conf en récupérant de nouveau les paramètres du fichier de conf :
	getConf
}


updateReposConfFiles() { # Mets à jour les fichiers de conf .repo en allant les récupérer sur le serveur de repo
	# Si on est autorisé à mettre à jour les fichiers de conf de repos et si le serveur de repos le gère
	if [ "$REPOSERVER_MANAGE_CLIENTS_REPOSCONF" == "yes" ] && [ "$REPOSERVER_ALLOW_REPOSFILES_UPDATE" == "yes" ];then
		echo -ne " → Mise à jour des fichiers de configuration des repos : "

		# Création d'un répertoire temporaire pour télécharger les fichiers .repo
		rm -rf /tmp/linuxautoupdate/reposconf/ &&
		mkdir -p /tmp/linuxautoupdate/reposconf/ && 
		cd /tmp/linuxautoupdate/reposconf/ &&

		# Récupération des fichiers depuis le serveur de repo
		if [ "$OS_FAMILY" == "Redhat" ];then
			wget -q -r -np -nH --cut-dirs=3 -R index.html "http://${REPOSERVER_PROFILES_URL}/${SERVER_TYPE}/*.repo"
			RESULT=$?
		fi

		if [ "$OS_FAMILY" == "Debian" ];then
			wget -q -r -np -nH --cut-dirs=3 -R index.html "http://${REPOSERVER_PROFILES_URL}/${SERVER_TYPE}/*.list"
			RESULT=$?
		fi

		if [ "$RESULT" -ne "0" ];then
			echo -e "[$JAUNE ERREUR $RESET] lors du téléchargement des fichiers de conf .repo depuis ${REPOSERVER_URL}"
			return 2
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
			return 1
		fi

		if [ "$REPOSERVER_ALLOW_REPOSFILES_UPDATE" != "yes" ];then
			echo -e "${JAUNE}Paramètre ALLOW_REPOSFILES_OVERWRITE=\"no\" ou est vide; Rien n'est fait, la configuration des fichiers de repos reste inchangée$RESET"
			return 1
		fi
	fi
	echo ""
}

main () {
	# Fail-level :
	# 1 = quitte à la moindre erreur (module désactivé, le serveur ne gère pas le même OS, erreur mineure, critique)
	# 2 = quitte seulement en cas d'erreur critique
	# 3 = continue même en cas d'erreur critique (ex : impossible de récupérer la conf du serveur de repo), la machine se mettre à jour selon la conf actuellement en place dans son fichier de conf

	# Codes de retour :
	# Aucune erreur : 	return 0
	# Erreur mineure :  return 1
	# Erreur critique : return 2

	echo -e " Exécution du module ${JAUNE}reposerver${RESET}"

	# On récupère la configuration du module, en l'occurence la configuration du serveur de repo
	getModConf
	RESULT="$?"
	if [ "$FAILLEVEL" -le "2" ] && [ "$RESULT" -gt "0" ];then (( MOD_ERROR++ )); clean_exit;fi 	# Si FAILLEVEL = 1 ou 2
	if [ "$FAILLEVEL" -eq "3" ] && [ "$RESULT" -gt "0" ];then return 1;fi 	 					# Si FAILLEVEL = 3 et qu'il y a une erreur au chargement de la conf du module alors on quitte le module sans pour autant quitter repomanager (clean_exit)

	# On met à jour la configuration du serveur de repo distant en lui demandant de renvoyer sa conf
	updateModConf
	RESULT="$?"
	if [ "$FAILLEVEL" -eq "1" ] && [ "$RESULT" -gt "0" ];then (( MOD_ERROR++ )); clean_exit;fi
	if [ "$FAILLEVEL" -eq "2" ] && [ "$RESULT" -ge "2" ];then (( MOD_ERROR++ )); clean_exit;fi
	if [ "$FAILLEVEL" -eq "3" ] && [ "$RESULT" -gt "0" ];then return 1;fi 						# Si FAILLEVEL = 3 et qu'il y a une erreur au chargement de la conf du module alors on quitte le module sans pour autant quitter repomanager (clean_exit)

	# On vérifie que la configuration du serveur de repo est compatible avec notre OS
	preCheck
	RESULT="$?"
	if [ "$FAILLEVEL" -eq "1" ] && [ "$RESULT" -gt "0" ];then (( MOD_ERROR++ )); clean_exit;fi
	if [ "$FAILLEVEL" -eq "2" ] && [ "$RESULT" -ge "2" ];then (( MOD_ERROR++ )); clean_exit;fi

	# On met à jour notre configuration à partir du serveur de repo (profils), si cela est autorisé des deux côtés
	updateConfFile
	RESULT="$?"
	if [ "$FAILLEVEL" -eq "1" ] && [ "$RESULT" -gt "0" ];then (( MOD_ERROR++ )); clean_exit;fi
	if [ "$FAILLEVEL" -eq "2" ] && [ "$RESULT" -ge "2" ];then (( MOD_ERROR++ )); clean_exit;fi

	# On met à jour notre configuration des repos à partir du serveurs de repo (profils), si cela est autorisé des deux côtés
	updateReposConfFiles
	RESULT="$?"
	if [ "$FAILLEVEL" -eq "1" ] && [ "$RESULT" -gt "0" ];then (( MOD_ERROR++ )); clean_exit;fi
	if [ "$FAILLEVEL" -eq "2" ] && [ "$RESULT" -ge "2" ];then (( MOD_ERROR++ )); clean_exit;fi
}