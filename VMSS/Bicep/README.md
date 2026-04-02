# 🚀 Déploiement IaaS Haute Disponibilité sur Azure (Bicep)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Azure](https://img.shields.io/badge/azure-%230072C6.svg?style=flat&logo=microsoftazure&logoColor=white)](https://azure.microsoft.com/)
[![Bicep](https://img.shields.io/badge/Bicep-IaC-blue?logo=microsoftazure)](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)

Ce dépôt contient le code **Bicep** (Infrastructure as Code) permettant de déployer une architecture web complète, sécurisée, hautement disponible et élastique sur le cloud Microsoft Azure. 

Ce projet illustre la mise en place d'une infrastructure "Scale-Out" capable d'absorber des pics de trafic imprévisibles grâce à l'auto-scaling, tout en garantissant un accès sécurisé pour l'administration.

## 🏗️ Architecture déployée

Le script `main.bicep` provisionne automatiquement les ressources suivantes :

* **🌐 Réseau (VNet & Subnet) :** Un réseau virtuel dédié (`10.0.0.0/16`) avec un sous-réseau isolé pour les serveurs web (`10.0.1.0/24`).
* **🛡️ Sécurité (NSG) :** Un groupe de sécurité réseau appliquant le principe du moindre privilège, autorisant uniquement le trafic entrant **HTTP (Port 80)** et **SSH (Port 22)**.
* **⚖️ Load Balancer Standard :** Un équilibreur de charge public avec adresse IP statique, sonde de santé (Health Probe) et des règles **NAT Inbound** pour le routage SSH.
* **🖥️ Virtual Machine Scale Set (VMSS) :** Un groupe de machines virtuelles identiques sous **Ubuntu 22.04 LTS**, comprenant :
  * **Bootstrapping automatique :** Installation et configuration de Nginx au démarrage via `Cloud-init` (Custom Data).
  * **Auto-scaling :** Règles d'élasticité basées sur le CPU (Scale-out si CPU > 75%, Scale-in si CPU < 25%).
  * **Sécurité SSH :** Authentification stricte par clé publique (sans mot de passe).

## 📋 Prérequis

Avant de lancer le déploiement, vous devez disposer de :

1. Un compte Microsoft Azure actif.
2. [Azure CLI](https://docs.microsoft.com/fr-fr/cli/azure/install-azure-cli) installé sur votre machine (ou utiliser l'Azure Cloud Shell).
3. Une paire de clés SSH générée sur votre machine locale (ou dans le Cloud Shell). 
   * Pour la générer : `ssh-keygen -t rsa -b 4096`

## 🚀 Guide de déploiement

### 1. Cloner le dépôt
` ` `bash
git clone https://github.com/NicoBOB/Microsoft-Azure.git
cd Microsoft-Azure
` ` `

### 2. S'authentifier sur Azure
` ` `bash
az login
` ` `
*(Si vous avez plusieurs abonnements, sélectionnez le bon avec `az account set --subscription <ID>`)*

### 3. Lancer le déploiement
Exécutez la commande suivante en remplaçant `<VOTRE_GROUPE_DE_RESSOURCES>` par le nom de votre groupe de ressources Azure. Le script lira automatiquement votre clé publique SSH locale.

` ` `bash
az deployment group create \
  --resource-group <VOTRE_GROUPE_DE_RESSOURCES> \
  --template-file main.bicep \
  --parameters adminPublicKey="$(cat ~/.ssh/id_rsa.pub)"
` ` `

*Note : Le paramètre optionnel `vmSku` peut être modifié à la volée si la taille `Standard_D2s_v3` n'est pas disponible dans votre région (ex: `--parameters vmSku="Standard_B2s"`).*

## 🔌 Utilisation et Tests

Une fois le déploiement terminé avec succès (`"provisioningState": "Succeeded"`) :

1. **Accès Web :** Récupérez l'adresse IP publique de votre Load Balancer dans le portail Azure et ouvrez-la dans votre navigateur. Vous devriez voir la page d'accueil Nginx affichant le nom de l'instance.
2. **Accès SSH (Administration) :** Pour vous connecter à une instance spécifique derrière le Load Balancer, vous devez utiliser le port NAT attribué dynamiquement (ex: 50000, 50001, etc.).
   ` ` `bash
   ssh azureuser@<IP_PUBLIQUE_DU_LB> -p 50000
   ` ` `
3. **Test d'Auto-scaling :** Connectez-vous en SSH, installez l'outil `stress` (`sudo apt-get install stress`) et chargez le CPU (`stress --cpu 4 --timeout 600`). Observez la création automatique de nouvelles instances depuis le portail Azure.

## 🧹 Nettoyage

Pour éviter des frais inutiles, pensez à supprimer les ressources une fois vos tests terminés. Vous pouvez supprimer entièrement le groupe de ressources :

` ` `bash
az group delete --name <VOTRE_GROUPE_DE_RESSOURCES> --yes --no-wait
` ` `

## 👨‍💻 Auteur

**Nicolas BODAINE**
* GitHub : [@NicoBOB](https://github.com/NicoBOB)

## 📄 Licence

Ce projet est sous licence MIT
