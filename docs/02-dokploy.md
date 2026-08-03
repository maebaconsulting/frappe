# Déploiement dans Dokploy

Créer le service Compose, renseigner les variables, rattacher le domaine, déployer.

## Créer le service

Le service doit être de type **Docker Compose**, et non Docker Stack. La pile utilise
trois conteneurs éphémères, `configurator`, `create-site` et `migrator`, dont les
autres services dépendent par la condition `service_completed_successfully`. En mode
Swarm, ces conteneurs seraient redémarrés en boucle et la condition ne serait jamais
satisfaite.

1. Créer un projet, puis un service de type **Compose**.
2. Source : **Git**, dépôt `https://github.com/maebaconsulting/frappe.git`, branche
   `main`.
3. Chemin du fichier Compose : `./docker-compose.yml`.

## Variables d'environnement

À saisir dans l'onglet **Environment** du service :

```txt
ERP_IMAGE=ghcr.io/maebaconsulting/frappe:version-16
SITE_NAME=erp.mowoapp.com
ADMIN_PASSWORD=un-mot-de-passe-fort
DB_ROOT_PASSWORD=un-autre-mot-de-passe-fort
MIGRATE_SITES=true
```

`SITE_NAME` alimente à la fois la création du site et la variable
`FRAPPE_SITE_NAME_HEADER` du service `frontend`. Les deux valeurs doivent rester
identiques au domaine servi par Traefik. Frappe résout le site à partir de l'en-tête
Host : toute divergence produit un « Site not found » qui ressemble à une panne
générale de la pile alors que tous les conteneurs tournent normalement.

Le fichier `.env` local est exclu du dépôt par `.gitignore`. `.env.example` sert de
modèle.

## Domaine et certificat

Sur le service **`frontend`**, onglet **Domains**, ajouter un domaine :

| Champ | Valeur |
| --- | --- |
| Host | `erp.mowoapp.com` |
| Path | `/` |
| Container port | `8080` |
| HTTPS | activé |
| Certificate | Let's Encrypt |

Aucun port n'est publié vers l'hôte dans le fichier Compose. Traefik est le seul point
d'entrée. Le service `frontend` est rattaché au réseau externe `dokploy-network` en
plus du réseau interne, ce qui le rend joignable par Traefik ; les autres services
restent isolés sur le réseau interne.

## Premier déploiement

Le conteneur `create-site` crée le site et installe les six applications. Compter
plusieurs minutes. Suivre sa sortie dans les journaux du service : c'est là
qu'apparaissent les erreurs de mot de passe de base de données ou de connexion.

La commande de création est idempotente. Si `sites/erp.mowoapp.com` existe déjà, le
conteneur sort en code 0 sans rien toucher, ce qui rend les redéploiements Dokploy
sans danger pour l'installation en place.

Le conteneur `migrator` prend ensuite le relais et applique `bench migrate`. Sur un
site fraîchement créé l'opération est brève. C'est seulement une fois qu'il s'est
terminé en code 0 que `backend`, `websocket`, `scheduler` et les deux files démarrent.

[← Construction et publication de l'image](01-image.md) · [Index](../README.md) · [Réglages Cloudflare →](03-cloudflare.md)
