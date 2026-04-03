// ============================================================================
// FICHIER DE DÉPLOIEMENT BICEP - Infrastructure HypeKicks
// ============================================================================
// Ce fichier décrit toute l'infrastructure Azure nécessaire pour héberger
// le site web HypeKicks : réseau, sécurité, load balancer, machines virtuelles
// et auto-scaling. Azure lira ce fichier et créera automatiquement toutes
// les ressources décrites ci-dessous.
// ============================================================================

// ============================================================================
// PARAMÈTRES
// ============================================================================
// Les paramètres sont des valeurs que l'utilisateur peut fournir au moment
// du déploiement. Ils rendent le template réutilisable et personnalisable.
// Le décorateur @description() ajoute une aide textuelle visible dans le portail Azure.
// ============================================================================

// Nom d'utilisateur administrateur pour se connecter aux machines virtuelles.
// Par défaut 'azureuser', mais peut être changé au déploiement.
@description('Identifiant administrateur pour les machines virtuelles')
param adminUsername string = 'azureuser'

// Clé publique SSH : c'est le contenu du fichier ~/.ssh/id_rsa.pub sur votre machine.
// Elle permet de se connecter aux VMs sans mot de passe, de manière sécurisée.
// Pas de valeur par défaut → l'utilisateur DOIT la fournir au déploiement.
@description('Cle publique SSH pour authentification (Contenu du fichier id_rsa.pub)')
param adminPublicKey string

// Région Azure où seront créées les ressources (ex: 'francecentral', 'westeurope').
// Par défaut, on utilise la même région que le Resource Group parent.
// resourceGroup().location est une fonction Bicep qui récupère cette info automatiquement.
@description('Localisation des ressources')
param location string = resourceGroup().location

// Taille (SKU) des machines virtuelles. 'Standard_D2s_v3' = 2 vCPUs, 8 Go RAM.
// Peut être changé pour des VMs plus petites ou plus grandes selon les besoins.
@description('Taille des instances de machine virtuelle')
param vmSku string = 'Standard_D2s_v3'

// ============================================================================
// VARIABLES
// ============================================================================
// Les variables stockent des valeurs calculées ou des noms réutilisés plusieurs
// fois dans le fichier. Contrairement aux paramètres, elles ne sont pas
// modifiables par l'utilisateur au moment du déploiement.
// ============================================================================

// --- Variables de nommage ---
// Chaque ressource Azure a besoin d'un nom unique. On les centralise ici
// pour faciliter la maintenance. Les préfixes suivent les conventions Azure :
//   vnet- = Virtual Network, snet- = Subnet, pip- = Public IP,
//   lb- = Load Balancer, vmss- = VM Scale Set, nsg- = Network Security Group
var vnetName = 'vnet-hypekicks'       // Nom du réseau virtuel
var subnetName = 'snet-web'           // Nom du sous-réseau pour les serveurs web
var publicIpName = 'pip-lb-hypekicks' // Nom de l'adresse IP publique du load balancer
var lbName = 'lb-hypekicks'           // Nom du load balancer (répartiteur de charge)
var vmssName = 'vmss-web-hypekicks'   // Nom du groupe de machines virtuelles (Scale Set)
var nsgName = 'nsg-web-hypekicks'     // Nom du groupe de sécurité réseau (pare-feu)

// --- Script Cloud-Init (Bootstrap) ---
// Cloud-Init est un script qui s'exécute automatiquement au PREMIER démarrage
// de chaque machine virtuelle. Ici, il :
//   1. Met à jour la liste des paquets Linux (apt-get update)
//   2. Installe le serveur web Nginx
//   3. Crée une page HTML de bienvenue avec le nom de la machine (hostname)
//   4. Redémarre Nginx pour appliquer la configuration
// base64() encode le script en Base64, format requis par Azure pour le transmettre.
var customData = base64('''#!/bin/bash
apt-get update
apt-get install -y nginx
echo "<h1>Bienvenue sur HypeKicks !</h1><p>Servi par l'instance : $(hostname)</p>" > /var/www/html/index.html
systemctl restart nginx
''')

// ============================================================================
// RESSOURCES
// ============================================================================
// Chaque bloc 'resource' décrit une ressource Azure à créer.
// La syntaxe est : resource <nom_symbolique> '<type_Azure>@<version_API>' = { ... }
//   - <nom_symbolique> : nom utilisé dans CE fichier pour référencer la ressource
//   - <type_Azure> : type officiel de la ressource dans Azure
//   - <version_API> : version de l'API Azure utilisée pour créer cette ressource
// ============================================================================

// --- 0. Groupe de Sécurité Réseau (NSG) ---
// Un NSG agit comme un pare-feu virtuel. Il contient des règles qui autorisent
// ou bloquent le trafic réseau entrant/sortant vers les ressources associées.
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: nsgName                 // Nom de la ressource dans Azure
  location: location            // Région de déploiement
  properties: {
    securityRules: [            // Liste des règles de sécurité (filtrage du trafic)
      {
        name: 'Allow-HTTP'      // Règle n°1 : Autoriser le trafic web (HTTP)
        properties: {
          priority: 1000        // Priorité de la règle (plus petit = évalué en premier)
          access: 'Allow'       // Action : autoriser le trafic
          direction: 'Inbound'  // Direction : trafic ENTRANT (depuis Internet vers nos VMs)
          protocol: 'Tcp'       // Protocole réseau : TCP (utilisé par HTTP)
          sourcePortRange: '*'  // Port source : n'importe lequel (le navigateur choisit un port aléatoire)
          destinationPortRange: '80'      // Port de destination : 80 = port standard HTTP
          sourceAddressPrefix: '*'        // Adresse source : n'importe quelle IP (tout Internet)
          destinationAddressPrefix: '*'   // Adresse destination : toutes nos ressources dans le sous-réseau
        }
      }
      {
        name: 'Allow-SSH'       // Règle n°2 : Autoriser les connexions SSH (administration à distance)
        properties: {
          priority: 1010        // Priorité légèrement inférieure à HTTP (évalué après)
          access: 'Allow'       // Action : autoriser
          direction: 'Inbound'  // Direction : trafic entrant
          protocol: 'Tcp'       // Protocole : TCP (utilisé par SSH)
          sourcePortRange: '*'  // Port source : n'importe lequel
          destinationPortRange: '22'      // Port destination : 22 = port standard SSH
          sourceAddressPrefix: '*'        // Source : toute IP (en production, on restreindrait à notre IP)
          destinationAddressPrefix: '*'   // Destination : toutes nos ressources
        }
      }
    ]
  }
}

// --- 1. Réseau Virtuel ---
// Un VNet (Virtual Network) est un réseau privé isolé dans Azure.
// C'est l'équivalent d'un réseau local (LAN) dans le cloud.
// Les VMs placées dans ce réseau peuvent communiquer entre elles en privé.
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'          // Plage d'adresses IP du réseau : 10.0.0.0 à 10.0.255.255
                                // Le "/16" signifie que les 16 premiers bits sont fixes → ~65 000 adresses disponibles
      ]
    }
    subnets: [                  // Sous-réseaux : divisions logiques du VNet
      {
        name: subnetName        // Nom du sous-réseau dédié aux serveurs web
        properties: {
          addressPrefix: '10.0.1.0/24'  // Plage du sous-réseau : 10.0.1.0 à 10.0.1.255 (254 adresses utilisables)
          networkSecurityGroup: {
            id: nsg.id          // On associe le NSG (pare-feu) créé plus haut à ce sous-réseau.
                                // nsg.id fait référence au nom symbolique 'nsg' défini au bloc précédent.
                                // Bicep gère automatiquement l'ordre de création (dépendance implicite).
          }
        }
      }
    ]
  }
}

// --- 2. Adresse IP Publique ---
// Une IP publique est une adresse accessible depuis Internet.
// Sans elle, personne ne pourrait accéder à notre site web depuis l'extérieur.
// Cette IP sera attachée au Load Balancer (pas directement aux VMs).
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'            // SKU Standard : nécessaire pour fonctionner avec un Load Balancer Standard.
                                // (Le SKU 'Basic' est moins fiable et sera bientôt retiré par Azure)
  }
  properties: {
    publicIPAllocationMethod: 'Static'  // 'Static' = l'adresse IP ne change jamais, même après un redémarrage.
                                        // 'Dynamic' changerait à chaque redémarrage (problématique pour un site web).
  }
}

// --- 3. Load Balancer ---
// Le Load Balancer (répartiteur de charge) distribue le trafic entrant
// entre plusieurs machines virtuelles. Avantages :
//   - Si une VM tombe en panne, le trafic est redirigé vers les autres
//   - La charge est répartie équitablement entre les VMs
//   - Les utilisateurs accèdent à UNE seule IP (celle du LB), pas aux VMs directement
resource lb 'Microsoft.Network/loadBalancers@2023-04-01' = {
  name: lbName
  location: location
  sku: {
    name: 'Standard'            // SKU Standard : supporte les zones de disponibilité et le VMSS
  }
  properties: {

    // --- Frontend : le "côté public" du Load Balancer ---
    // C'est l'interface qui reçoit le trafic depuis Internet via l'IP publique.
    frontendIPConfigurations: [
      {
        name: 'LoadBalancerFrontEnd'    // Nom de cette configuration frontend
        properties: {
          publicIPAddress: {
            id: publicIp.id     // On attache l'IP publique créée plus haut au frontend du LB.
                                // Tout le trafic arrivant sur cette IP sera traité par le LB.
          }
        }
      }
    ]

    // --- Backend Pool : le "côté privé" du Load Balancer ---
    // C'est le groupe de VMs vers lesquelles le LB redirige le trafic.
    // Les VMs du VMSS s'ajouteront automatiquement à ce pool.
    backendAddressPools: [
      {
        name: 'BackendPool'     // Nom du pool. Les VMs du Scale Set seront enregistrées ici.
      }
    ]

    // --- Sonde de santé (Health Probe) ---
    // Le LB vérifie régulièrement que chaque VM fonctionne correctement.
    // Si une VM ne répond plus, elle est retirée du pool (plus de trafic envoyé).
    probes: [
      {
        name: 'HealthProbe-Port80'      // Nom de la sonde de santé
        properties: {
          protocol: 'Tcp'               // Protocole utilisé pour le test : TCP
          port: 80                      // Port testé : 80 (HTTP). Si Nginx répond → VM en bonne santé.
          intervalInSeconds: 5          // Fréquence du test : toutes les 5 secondes
          numberOfProbes: 2             // Nombre d'échecs consécutifs avant de considérer la VM "en panne"
        }
      }
    ]

    // --- Règle de répartition de charge ---
    // Définit COMMENT le trafic est redistribué du frontend vers le backend.
    loadBalancingRules: [
      {
        name: 'LBRule-Port80'           // Nom de la règle
        properties: {
          frontendIPConfiguration: {
            // Référence vers la configuration frontend définie plus haut.
            // resourceId() construit l'identifiant Azure complet de la sous-ressource.
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'LoadBalancerFrontEnd')
          }
          backendAddressPool: {
            // Référence vers le pool backend (groupe de VMs cibles)
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'BackendPool')
          }
          probe: {
            // Référence vers la sonde de santé : seules les VMs "saines" reçoivent du trafic
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'HealthProbe-Port80')
          }
          protocol: 'Tcp'              // Protocole de la règle : TCP
          frontendPort: 80             // Port d'écoute côté public (Internet → LB)
          backendPort: 80              // Port de destination côté privé (LB → VMs)
                                       // Ici les deux sont 80, mais on pourrait rediriger vers un autre port.
          idleTimeoutInMinutes: 15     // Durée max d'inactivité (en minutes) avant de fermer la connexion
        }
      }
    ]

    // --- Pool NAT entrant pour SSH ---
    // NAT (Network Address Translation) permet d'accéder individuellement
    // à chaque VM via SSH à travers le Load Balancer.
    // Chaque VM recevra un port unique entre 50000 et 50099.
    // Exemple : ssh user@<IP_publique> -p 50000 → VM n°1
    //           ssh user@<IP_publique> -p 50001 → VM n°2
    inboundNatPools: [
      {
        name: 'NatPool-SSH'             // Nom du pool NAT
        properties: {
          frontendIPConfiguration: {
            // Référence vers l'IP publique du frontend
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'LoadBalancerFrontEnd')
          }
          protocol: 'Tcp'              // Protocole : TCP (utilisé par SSH)
          frontendPortRangeStart: 50000 // Premier port public attribué (pour la 1ère VM)
          frontendPortRangeEnd: 50099   // Dernier port public attribué (jusqu'à 100 VMs possibles)
          backendPort: 22               // Port SSH standard sur chaque VM (toujours 22)
        }
      }
    ]
  }
}

// --- 4. Virtual Machine Scale Set (VMSS) ---
// Un VMSS est un groupe de machines virtuelles IDENTIQUES, gérées ensemble.
// Avantages :
//   - Toutes les VMs ont la même configuration (OS, logiciels, réseau)
//   - On peut augmenter ou diminuer le nombre de VMs facilement (scaling)
//   - Azure gère la création, la mise à jour et la suppression des VMs
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-03-01' = {
  name: vmssName
  location: location
  sku: {
    name: vmSku                 // Taille de chaque VM (paramètre défini plus haut : Standard_D2s_v3)
    tier: 'Standard'            // Niveau de service Standard
    capacity: 2                 // 2 instances par défaut au déploiement
                                // L'auto-scaling pourra ensuite ajuster ce nombre automatiquement
  }
  properties: {
    overprovision: false        // false = Azure crée exactement le nombre de VMs demandé.
                                // true (par défaut) crée des VMs en surplus puis supprime l'excédent
                                // pour garantir le nombre voulu (plus rapide mais peut causer des surprises).
    upgradePolicy: {
      mode: 'Manual'            // 'Manual' = les mises à jour du modèle ne s'appliquent PAS automatiquement
                                // aux VMs existantes. Il faut les mettre à jour manuellement.
                                // Autres options : 'Automatic' ou 'Rolling' (progressif).
    }

    // --- Profil de la machine virtuelle ---
    // Ce "profil" est le modèle (template) appliqué à CHAQUE VM du Scale Set.
    virtualMachineProfile: {

      // --- Configuration du système d'exploitation ---
      osProfile: {
        computerNamePrefix: 'vmweb'     // Préfixe du nom de chaque VM. Azure ajoute un suffixe unique.
                                        // Résultat : vmweb000000, vmweb000001, etc.
        adminUsername: adminUsername     // Nom d'utilisateur admin (paramètre : 'azureuser' par défaut)
        customData: customData          // Script Cloud-Init encodé en Base64 (installe Nginx au démarrage)
        linuxConfiguration: {
          disablePasswordAuthentication: true  // Interdit la connexion par mot de passe → plus sécurisé.
                                              // Seule la clé SSH sera acceptée pour se connecter.
          ssh: {
            publicKeys: [
              {
                // Chemin où Azure dépose la clé publique sur la VM Linux.
                // ${adminUsername} est une interpolation : remplacé par la valeur du paramètre (ex: 'azureuser')
                path: '/home/${adminUsername}/.ssh/authorized_keys'
                keyData: adminPublicKey // Contenu de la clé publique SSH fournie en paramètre
              }
            ]
          }
        }
      }

      // --- Configuration du stockage (disques et image OS) ---
      storageProfile: {
        imageReference: {               // Image de base pour le système d'exploitation
          publisher: 'Canonical'        // Éditeur : Canonical (créateur d'Ubuntu)
          offer: '0001-com-ubuntu-server-jammy'  // Offre : Ubuntu Server 22.04 "Jammy Jellyfish"
          sku: '22_04-lts-gen2'         // SKU : version LTS (support long terme) de génération 2
          version: 'latest'             // Version : toujours la plus récente disponible
        }
        osDisk: {                       // Configuration du disque système (OS)
          createOption: 'FromImage'     // Le disque est créé à partir de l'image Ubuntu ci-dessus
          caching: 'ReadWrite'          // Mise en cache du disque en lecture ET écriture (meilleures performances)
          managedDisk: {
            storageAccountType: 'Standard_LRS'  // Type de stockage : Standard (HDD) avec réplication locale (LRS).
                                                // LRS = 3 copies dans le même datacenter. Moins cher que Premium (SSD).
          }
        }
      }

      // --- Configuration réseau de chaque VM ---
      networkProfile: {
        networkInterfaceConfigurations: [   // Configuration de la carte réseau virtuelle de chaque VM
          {
            name: 'nic-vmss'               // Nom de l'interface réseau
            properties: {
              primary: true                // C'est l'interface réseau principale de la VM
              ipConfigurations: [          // Configuration IP de cette interface
                {
                  name: 'ipconfig-vmss'    // Nom de la configuration IP
                  properties: {
                    subnet: {
                      // Connecte chaque VM au sous-réseau 'snet-web' du VNet.
                      // vnet.properties.subnets[0].id récupère l'ID du premier sous-réseau défini dans le VNet.
                      id: vnet.properties.subnets[0].id
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        // Inscrit chaque VM dans le pool backend du Load Balancer.
                        // Ainsi, le LB sait vers quelles VMs envoyer le trafic web.
                        id: lb.properties.backendAddressPools[0].id
                      }
                    ]
                    loadBalancerInboundNatPools: [
                      {
                        // Associe chaque VM au pool NAT SSH du Load Balancer.
                        // Chaque VM recevra un port unique (50000, 50001...) pour l'accès SSH.
                        id: resourceId('Microsoft.Network/loadBalancers/inboundNatPools', lbName, 'NatPool-SSH')
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
}

// --- 5. Règles d'Auto-Scaling ---
// L'auto-scaling ajuste automatiquement le nombre de VMs en fonction de la charge.
// Si le CPU est élevé → on ajoute des VMs (scale-out).
// Si le CPU est bas → on retire des VMs (scale-in) pour économiser de l'argent.
resource autoscale 'Microsoft.Insights/autoscaleSettings@2022-10-01' = {
  name: 'autoscale-vmss-hypekicks'
  location: location
  properties: {
    targetResourceUri: vmss.id  // Ressource cible : notre VMSS. C'est lui qui sera mis à l'échelle.
    enabled: true               // Active l'auto-scaling (peut être désactivé sans supprimer la config)
    profiles: [                 // Liste des profils d'auto-scaling (on peut en avoir plusieurs, ex: jour/nuit)
      {
        name: 'AutoCreatedScaleCondition'   // Nom du profil
        capacity: {
          minimum: '2'          // Nombre MINIMUM de VMs : jamais moins de 2 (haute disponibilité)
          maximum: '4'          // Nombre MAXIMUM de VMs : jamais plus de 4 (contrôle des coûts)
          default: '2'          // Nombre par défaut si les métriques ne sont pas disponibles
        }
        rules: [                // Règles qui déclenchent le scaling

          // === Règle 1 : SCALE-OUT (ajout de VMs quand la charge augmente) ===
          {
            metricTrigger: {                        // Condition de déclenchement basée sur une métrique
              metricName: 'Percentage CPU'          // Métrique surveillée : pourcentage d'utilisation CPU
              metricResourceUri: vmss.id            // Ressource surveillée : notre VMSS
              timeGrain: 'PT1M'                     // Granularité : données collectées chaque minute (PT1M = Period Time 1 Minute)
              statistic: 'Average'                  // Statistique utilisée : moyenne des VMs
              timeWindow: 'PT5M'                    // Fenêtre d'observation : 5 dernières minutes
              timeAggregation: 'Average'            // Agrégation sur la fenêtre : moyenne
              operator: 'GreaterThan'               // Opérateur de comparaison : supérieur à
              threshold: 75                         // Seuil : 75% de CPU → on considère que c'est trop chargé
            }
            scaleAction: {                          // Action à effectuer quand la condition est remplie
              direction: 'Increase'                 // Direction : augmenter le nombre de VMs
              type: 'ChangeCount'                   // Type : changer le nombre d'instances d'un montant fixe
              value: '1'                            // Valeur : ajouter 1 VM à la fois
              cooldown: 'PT5M'                      // Temps de repos : attendre 5 min avant de re-scaler
                                                    // Évite d'ajouter trop de VMs d'un coup pendant un pic
            }
          }

          // === Règle 2 : SCALE-IN (retrait de VMs quand la charge diminue) ===
          {
            metricTrigger: {
              metricName: 'Percentage CPU'          // Même métrique : utilisation CPU
              metricResourceUri: vmss.id            // Même ressource : notre VMSS
              timeGrain: 'PT1M'                     // Collecte chaque minute
              statistic: 'Average'                  // Moyenne des VMs
              timeWindow: 'PT5M'                    // Sur les 5 dernières minutes
              timeAggregation: 'Average'            // Agrégation : moyenne
              operator: 'LessThan'                  // Opérateur : inférieur à
              threshold: 25                         // Seuil : 25% de CPU → les VMs sont sous-utilisées
            }
            scaleAction: {
              direction: 'Decrease'                 // Direction : diminuer le nombre de VMs
              type: 'ChangeCount'                   // Type : changement par un montant fixe
              value: '1'                            // Valeur : retirer 1 VM à la fois
              cooldown: 'PT5M'                      // Temps de repos : 5 min avant de re-scaler
                                                    // Évite de supprimer trop de VMs si la charge remonte vite
            }
          }
        ]
      }
    ]
  }
}
