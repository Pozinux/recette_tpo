import pandas
import os
import time, math
import sys
from threading import Thread
import paramiko
import logging
import numpy
from pprint import pprint

import constantes

print("\nVoici les projets connus :\n")
liste_projets = next(os.walk('./Projets'))[1]
print("\n".join(liste_projets))
dit_name_input = input("\nQuel est le nom du projet à recetter ? Veuillez entrer un des projets ci-dessus : ")
dit_name_input = str.strip(dit_name_input)
# nbr_lines = input("Combien de serveurs (ligne du DIT dans l'ordre) à prendre en compte ? (ex : 6) ")
nbr_lines = 40 # On recette par défaut les serveurs des 4 premières lignes du DIT.
# rhel_version = input("RHEL6 ou RHEL7 ? [6/7] ")
NOK_only = input("Ne voir que les résultats KO ? [O/N] ")

# mode_debug = input("Lancer en mode DEBUG ? [O/N] ")
mode_debug = "N"

if mode_debug == "O":
    logging.basicConfig(level=logging.INFO, format='%(message)s')  # Permet d'afficher les logs dans la console
    # logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')  # Permet d'afficher les logs dans la console (avec Date/heure + INFO affiché)
    # logging.basicConfig(level=logging.DEBUG, filename="vmfinder.log", filemode="w", format='%(asctime)s - %(levelname)s - %(message)s')  # Permet de logger dans un fichier    
 
projet_directory_path = constantes.SCRIPT_DIRECTORY_PATH + "\\Projets\\" + dit_name_input + "\\"  
dit_xlsx_file_path = projet_directory_path + dit_name_input + ".xlsx"  
dit_xlsx_filename_avec_ext = os.path.basename(dit_xlsx_file_path)  
dit_filename_sans_ext = os.path.splitext(dit_xlsx_filename_avec_ext)[0]  
dit_csv_file_path = projet_directory_path + dit_name_input + ".csv"  
file_out_tempo_path = projet_directory_path + dit_name_input + ".tmp"  
file_out_tempo_path_2 = projet_directory_path + dit_name_input + ".tmp2"
file_liste_serveurs_path = projet_directory_path + dit_name_input + ".list"

# Création liste des serveurs à recetter
file_liste_serveurs = open(file_liste_serveurs_path, "r")
data = file_liste_serveurs.read()
liste_des_serveurs_a_recetter = data.split('\n')
liste_des_serveurs_a_recetter = [x.strip() for x in liste_des_serveurs_a_recetter]
logging.info(f"\n################# Création liste serveurs à recetter : \n\n{liste_des_serveurs_a_recetter}")
file_liste_serveurs.close()


try:
    logging.info("\nTransformation du DIT excel en CSV...")
    pandas.set_option('display.expand_frame_repr', False) # Pour ne pas afficher des colonnes tronquées
    # Selects only somes columns but the order is not kept
    #df = pandas.read_excel(dit_xlsx_file_path, "Description Serveurs", skiprows=4, nrows=int(nbr_lines), usecols="D,F,G,X,Z,AA,AB,M,N,O,P,Q,R,S,T,U,AD")
    
    # skiprows = on ne met pas dans le df les 4 première lignes
    # nrows = nombre de lignes à mettre dans le df
    df = pandas.read_excel(dit_xlsx_file_path, "Description Serveurs", skiprows=4, nrows=int(nbr_lines))
    
    logging.info(f"\n################# Afficher le df récupéré de l'excel avant conversion des champs vide etc. : \n\n{df}")
except:
    print("\n\n\n/!\ Problème avec la récupération du fichier !\n\n- Avez-vous bien entré le bon nom de fichier et sans l'extension .xlsx ?\n- Le fichier existe-t-il bien avec une extension .xlsx ?\n\n")
    sys.exit(1) # So that we don't continue the script in case of except raised

# ANCIENNE VERSION qui inclue le controle des FS depuis le DIT
# Selects only these columns and keep this order following
# df = df[["Environnement", "Site",
         # "Nom serveur", "Type", "CPU",
         # "RAM", "OS Modèle", "Zone de confiance",
         # "ID VLAN Service", "Adresse IP Service",
         # "ID VLAN NAS", "Adresse IP NAS",
         # "ID VLAN Sauvegarde", "Adresse IP Sauvegarde",
         # "ID VLAN Admin", "Adresse IP Admin",
         # 'FS']]

# NOUVELLE VERSION qui inclue le controle des FS depuis la norme du client (que l'on défini directement dans le go-rhelX.sh)
df = df[["Environnement", "Site",
         "Nom serveur", "Type", "CPU",
         "RAM", "OS Modèle", "Zone de confiance",
         "ID VLAN Service", "Adresse IP Service",
         "ID VLAN NAS", "Adresse IP NAS",
         "ID VLAN Sauvegarde", "Adresse IP Sauvegarde",
         "ID VLAN Admin", "Adresse IP Admin"]]
         
# Ajouter une colonne vide à la fin pour qu'il y ait un ";" de plus sinon ça fait des bugs à la conversion plus tard
df["Empty"] = ""

# Zones de confiance
for zdc_dit, zdc_name in constantes.zdc_dict.items():
    df = df.replace(zdc_dit, zdc_name)

# Les champs vides null dans Excel se transforment en NaN dans un dataframe pandas.
# Ces NaN ne sont pas convertibles avec astype (voir plus loin) en int (car on ne veut pas les VLAN en float, c'est par défaut) donc on va remplacer les NaN par une valeur qui est convertible
# par exemple 999999 (pour pas que si c'est vide na conversion plante pour toute la colonne s'il trouve un seul champ non convertible).
df = df.fillna(999999)

# df converted to float (For example 2.0) but we only want int (2) -> Malheureusement ça ne fonctionne que par colonne. Si une ligne dans la colonne est vide, ça ne change pas le type dans cette colonne
# If the data cannot be convert into int, don't break the script with an error (par défaut c'est "raise" et dès qu'il rencontre qqchose qu'il ne peut convertir en int, le script plante.
df = df.astype(dtype=int, errors='ignore')

# print(df.info())  # Afficher le type des variables du df

# Insert empty column to simulate the swap column
df.insert(6, "swap", "")

logging.info(f"\n################# Afficher le df récupéré de l'excel après conversion des champs vide etc. : \n\n{df}")

# Remettre les champs nuls à nuls dans le dataframe pour pas avoir 99999 dans le csv :
#df = df.replace(999999, numpy.NaN)  # ---> ça remet le champ ID VLAN en float......
df = df.replace(999999, "")  # ---> ça remet le champ ID VLAN en object mais au moins pas du float......

logging.info(f"\n################# Afficher le df avec les champs de nouveau à NaN : \n\n{df}")

# print(df.info())  # Afficher le type des variables du df

# Converts df to csv without the index and header and specifies the caract separator
df.to_csv(dit_csv_file_path, index=False, header=False, sep=';')

# Afficher le CSV si on est en mode DEBUG 
logging.info("\n################# Affichage du fichier CSV généré :\n")
logging.info(f"dit_csv_file_path : {dit_csv_file_path}")
with open(dit_csv_file_path, "r") as f:
    contenu = f.read()
    logging.info(f"\n{contenu}")    
    
def run_ssh_command(ssh_command):
    stdin, stdout, stderr = ssh_client.exec_command(ssh_command, get_pty=True)
    result_stdout = stdout.read().decode('utf-8')
    result_list = [result_stdout]
    return result_list

logging.info("Création du fichier tmp avec une ligne correspondant à chaque serveur distant...")
file_in = open(dit_csv_file_path, "r")
file_output = open(file_out_tempo_path, "w")
for line in file_in:
    file_output.write(line.replace('Go"', ' G"').replace('Go "', ' G"').replace('G"', ' G"').replace('G "', ' G"').replace('g "', ' G"').replace('g"', ' G"').replace('go "', ' G"').replace('go"', ' G"').replace(' Go\n', ' G#').replace(' Go"', ' G"').replace(' Go "', ' G"').replace(' G"', ' G"').replace(' G "', ' G"').replace(' g "', ' G"').replace(' g"', ' G"').replace(' go "', ' G"').replace(' go"', ' G"').replace(' Go\n', ' G#').replace(' Go \n', ' G#').replace(' G\n', ' G#').replace(' G \n', ' G#').replace(' g \n', ' G#').replace(' g\n', ' G#').replace(' go \n', ' G#').replace(' go\n', ' G#').replace('Go\n', ' G#').replace('Go \n', ' G#').replace('G\n', ' G#').replace('G \n', ' G#').replace('g \n', ' G#').replace('g\n', ' G#').replace('go \n', ' G#').replace('go\n', ' G#'))
file_in.close()
file_output.close()

# Affichage du fichier CSV modifié avec une ligne par serveurs
logging.info(f"\n################# Chemin du fichier CSV modifié : \n\n{file_out_tempo_path}\n\n")
with open(file_out_tempo_path, "r") as f:
   contenu = f.read()
   logging.info(f"################# Affichage du fichier CSV modifié avec une ligne par serveurs : \n\n{contenu}")
   

# # Création d'un fichier ne contenant que les serveurs à recetter
logging.info("################# Création du fichier tmp2 avec une ligne correspondant à chaque serveur distant présents dans la liste source...\n")

open(file_out_tempo_path_2, "w").close()  # Vider le fichier en l'ouvrant + le refermant
file_output_2 = open(file_out_tempo_path_2, "a")

# Création liste des lignes csv
# Je créé une liste du fichier car comme j'itère directement le fichier, je devrais à chaque fois replacer le curseur au début
file_in = open(file_out_tempo_path, "r")
data_file_in = file_in.read()
liste_des_lignes_csv = data_file_in.split('\n')
logging.info(f"\n################# Création liste des lignes csv : \n\n{liste_des_lignes_csv}\n")
file_in.close()

logging.info(f"\n################# Création du fichier tmp2 \n")

for serv in liste_des_serveurs_a_recetter:
    logging.info(f"Recherche de {serv} dans le DIT...\n")    
    for line in liste_des_lignes_csv:
        if serv in line:
            file_output_2.write(line)
            file_output_2.write("\n")
            logging.info(f"{serv} trouvé dans la ligne {line}")
            break
        else:
            logging.info(f"{serv} non trouvé dans la ligne : {line}")
        
file_output_2.close()

# Affichage du fichier CSV modifié avec une ligne par serveurs seulement pour les serveurs à recetter
logging.info(f"\n################# Chemin du fichier CSV modifié (contient seulement les serveurs à recetter) : \n\n{file_out_tempo_path_2}\n\n")
with open(file_out_tempo_path_2, "r") as f:
   contenu = f.read()
   logging.info(f"################# Affichage du fichier CSV modifié avec une ligne par serveurs seulement pour les serveurs à recetter : \n\n{contenu}")



####### RECETTE pour chaque serveur du fichier tmp2 

# Récupérer le nom du serveur et créer un fichier csv à son nom avec sa ligne unique + transférer sur le serveur et lancer la recette
file_out = open(file_out_tempo_path_2, "r")
#file_out = open(file_out_tempo_path, "r")
for line in file_out:
    line_list = line.split(";")
    distant_server_name = line_list[2]
    enviro = line_list[0]

    logging.info(f"\n################# Recherche de la version de l'OS dans le DIT...\n\n")
    rhel_version_dit = line_list[7]
    logging.info(f"\nrhel_version_dit -> {rhel_version_dit}\n\n")
    if "6" in rhel_version_dit:
        rhel_version = "6"
        logging.info(f"\nRHEL {rhel_version} détectée dans le DIT...\n\n")
    elif "7" in rhel_version_dit:
        rhel_version = "7"
        logging.info(f"\nRHEL  détectée dans le DIT...\n\n")
        logging.info(f"\nRHEL {rhel_version} détectée dans le DIT...\n\n")
    else:
        rhel_version = "7"  # Par défaut si on ne trouve pas la version dans le DIT, on lance une recette pour une RHEL 7
        logging.info(f"\nPas de version RHEL détectée dans le DIT donc on applique la recette d'une RHEL 7...\n\n")

    distant_server_name_path_csv = projet_directory_path + "\\" + distant_server_name + ".csv"
    with open(distant_server_name_path_csv, "w") as f:
        f.write(line)
        
    # Ouverture de la connexion SSH au serveur distant
    ssh_client=paramiko.SSHClient()
    ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    serveur_distant_tiret_a = distant_server_name + "-a"
    print(f"\n----------------------- {serveur_distant_tiret_a} ({enviro}) -------------------------------\n")    
    logging.info(f"Connexion SSH au serveur distant {serveur_distant_tiret_a}...")   
    
    if rhel_version == "6":
        ssh_client.connect(serveur_distant_tiret_a, username='root', allow_agent=True)   
    elif rhel_version == "7":
        ssh_client.connect(serveur_distant_tiret_a, username=constantes.USER_SSH_RHEL7, allow_agent=True)         
    
    # Ouverture SSH
    s = ssh_client.get_transport().open_session()
    
    # set up the agent request handler to handle agent requests from the server
    paramiko.agent.AgentRequestHandler(s)
    
    # Création de l'arborescence recette, ref, opscenter etc.
    logging.info(f"Création de l'arborescence recette sur le serveur distant...")
    if rhel_version == "7":
        command = f"sudo mkdir -p {constantes.PATH_TO_RECETTE}ref/opscenter ; sudo chown -R {constantes.USER_SSH_RHEL7}:{constantes.USER_SSH_RHEL7} {constantes.PATH_TO_RECETTE}"
        logging.info("Executing {}".format(command))
        res_script = run_ssh_command(command)
        for item in res_script:
            if item:
                print(item)
    elif rhel_version == "6":
        command = f"mkdir -p {constantes.PATH_TO_RECETTE}ref/opscenter"
        logging.info("Executing {}".format(command))
        res_script = run_ssh_command(command)
        for item in res_script:
            if item:
                print(item)

    # Ouverture SFTP
    logging.info(f"Ouverture SFTP...")
    sftp_client = ssh_client.open_sftp()

    # Transfert SFTP go.sh
    logging.info(f"Transfert SFTP du go-rhel{rhel_version}.sh dans {constantes.PATH_TO_RECETTE}...")
    sftp_client.put(f'go-rhel{rhel_version}.sh', f'{constantes.PATH_TO_RECETTE}go-rhel{rhel_version}.sh')
    
    # Transfert SFTP config-toano.sh
    logging.info(f"Transfert SFTP du config-toano.sh dans {constantes.PATH_TO_RECETTE}...")
    sftp_client.put(f'config-toano.sh', f'{constantes.PATH_TO_RECETTE}config-toano.sh')

    # Transfert SFTP du nom_du_serveur.csv
    logging.info(f"Transfert SFTP du {distant_server_name}.csv...")
    sftp_client.put(distant_server_name_path_csv, f'{constantes.PATH_TO_RECETTE}' + distant_server_name + '.csv')

    # sftp multiple files OPSCENTER
    # Liste csv files sur le partage
    liste_of_files = os.listdir(fr'\\{constantes.PARTAGE_NAME}\SRCE\bull\script\opscenter-crossed-report\last\\')
    
    # Liste des fichiers CSV OPSCENTER sur le partage
    source_path = fr'\\{constantes.PARTAGE_NAME}\SRCE\bull\script\opscenter-crossed-report\last\\'
    for file in liste_of_files:
        logging.info(f'Transfert du fichier {file}...')
        sftp_client.put(f'{source_path}{file}', f'{constantes.PATH_TO_RECETTE}ref/opscenter/{file}')

    # sftp multiple files VLAN

    # Liste csv files sur le partage
    liste_of_files = os.listdir(fr'\\{constantes.PARTAGE_NAME}\SRCE\bull\script\vlan\\')

    # Liste des fichiers CSV VLAN sur le partage
    source_path = fr'\\{constantes.PARTAGE_NAME}\SRCE\bull\script\vlan\\'
    for file in liste_of_files:
        
        logging.info(f'Transfert du fichier {file}...')
        sftp_client.put(f'{source_path}{file}', f'{constantes.PATH_TO_RECETTE}ref/{file}')

    # Fermeture SFTP
    sftp_client.close()

    # Exécution de go.sh
    logging.info(f"Exécution du go-rhel{rhel_version}.sh et affichage des KO et des OK...")
    if rhel_version == "7":
        if NOK_only == "O":
            command = f"sudo chmod u+x {constantes.PATH_TO_RECETTE}go-rhel{rhel_version}.sh; sudo sh {constantes.PATH_TO_RECETTE}go-rhel{rhel_version}.sh -f {distant_server_name} | grep -e NOK"
        else:
            command = f"sudo chmod u+x {constantes.PATH_TO_RECETTE}go-rhel{rhel_version}.sh; sudo sh {constantes.PATH_TO_RECETTE}go-rhel{rhel_version}.sh -f {distant_server_name}"
    elif rhel_version == "6":
        if NOK_only == "O":
            command = f"chmod u+x {constantes.PATH_TO_RECETTE}go-rhel{rhel_version}.sh; sh {constantes.PATH_TO_RECETTE}go-rhel{rhel_version}.sh -f {distant_server_name} | grep -e NOK"
        else:
            command = f"chmod u+x {constantes.PATH_TO_RECETTE}go-rhel{rhel_version}.sh; sh {constantes.PATH_TO_RECETTE}go-rhel{rhel_version}.sh -f {distant_server_name}"

    logging.info("Executing {} \n".format(command))

    res_script = run_ssh_command(command)
    for item in res_script:
        print(item)
        
# Fermeture SSH
ssh_client.close()
file_out.close()

print(f"\n----------------------- RECETTE terminée ! -----------------------\n") 
