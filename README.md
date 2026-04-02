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
```bash
git clone [https://github.com/NicoBOB/Microsoft-Azure.git](https://github.com/NicoBOB/Microsoft-Azure.git)
cd Microsoft-Azure
