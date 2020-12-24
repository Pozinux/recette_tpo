import os     
     
# ---- A ANONYMISER -----     
     
SCRIPT_DIRECTORY_PATH = os.path.dirname(os.path.abspath(__file__))      
PARTAGE_NAME = "NOM_DU_SERVEUR_NAS"     
PATH_TO_RECETTE = "/tmp/recette/"  # Si modif, ne pas oublier de modifier le RECETTE_REMOTE_REP dans le go-rhelx.sh     
USER_SSH_RHEL7 = "toto"
     
# Zones de confiance     
zdc_dict = {'D1 (Zone Sensible 1)': 'D1',     
'D2 (Zone Sensible 2)': 'D2',     
            ....     
}    
