@description('Identifiant administrateur pour les machines virtuelles')
param adminUsername string = 'azureuser'

@description('Cle publique SSH pour authentification (Contenu du fichier id_rsa.pub)')
param adminPublicKey string

@description('Localisation des ressources')
param location string = resourceGroup().location

@description('Taille des instances de machine virtuelle')
param vmSku string = 'Standard_D2s_v3'

// --- Variables de nommage ---
var vnetName = 'vnet-hypekicks'
var subnetName = 'snet-web'
var publicIpName = 'pip-lb-hypekicks'
var lbName = 'lb-hypekicks'
var vmssName = 'vmss-web-hypekicks'
var nsgName = 'nsg-web-hypekicks'

// --- Script Cloud-Init (Bootstrap) ---
var customData = base64('''#!/bin/bash
apt-get update
apt-get install -y nginx
echo "<h1>Bienvenue sur HypeKicks !</h1><p>Servi par l'instance : $(hostname)</p>" > /var/www/html/index.html
systemctl restart nginx
''')

// --- 0. Groupe de Sécurité Réseau (NSG) ---
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-SSH'
        properties: {
          priority: 1010
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// --- 1. Réseau Virtuel ---
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// --- 2. Adresse IP Publique ---
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// --- 3. Load Balancer ---
resource lb 'Microsoft.Network/loadBalancers@2023-04-01' = {
  name: lbName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'LoadBalancerFrontEnd'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'BackendPool'
      }
    ]
    probes: [
      {
        name: 'HealthProbe-Port80'
        properties: {
          protocol: 'Tcp'
          port: 80
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'LBRule-Port80'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'LoadBalancerFrontEnd')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'BackendPool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'HealthProbe-Port80')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          idleTimeoutInMinutes: 15
        }
      }
    ]
    inboundNatPools: [
      {
        name: 'NatPool-SSH'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'LoadBalancerFrontEnd')
          }
          protocol: 'Tcp'
          frontendPortRangeStart: 50000
          frontendPortRangeEnd: 50099
          backendPort: 22
        }
      }
    ]
  }
}

// --- 4. Virtual Machine Scale Set (VMSS) ---
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-03-01' = {
  name: vmssName
  location: location
  sku: {
    name: vmSku
    tier: 'Standard'
    capacity: 2 // Modification : 2 instances par défaut au déploiement
  }
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Manual'
    }
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: 'vmweb'
        adminUsername: adminUsername
        customData: customData
        linuxConfiguration: {
          disablePasswordAuthentication: true
          ssh: {
            publicKeys: [
              {
                path: '/home/${adminUsername}/.ssh/authorized_keys'
                keyData: adminPublicKey
              }
            ]
          }
        }
      }
      storageProfile: {
        imageReference: {
          publisher: 'Canonical'
          offer: '0001-com-ubuntu-server-jammy'
          sku: '22_04-lts-gen2'
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          caching: 'ReadWrite'
          managedDisk: {
            storageAccountType: 'Standard_LRS'
          }
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'nic-vmss'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig-vmss'
                  properties: {
                    subnet: {
                      id: vnet.properties.subnets[0].id
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: lb.properties.backendAddressPools[0].id
                      }
                    ]
                    loadBalancerInboundNatPools: [
                      {
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
resource autoscale 'Microsoft.Insights/autoscaleSettings@2022-10-01' = {
  name: 'autoscale-vmss-hypekicks'
  location: location
  properties: {
    targetResourceUri: vmss.id
    enabled: true
    profiles: [
      {
        name: 'AutoCreatedScaleCondition'
        capacity: {
          minimum: '2' // Modification demandée
          maximum: '4' // Modification demandée
          default: '2' // Modification demandée
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 75
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 25
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
        ]
      }
    ]
  }
}
