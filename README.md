# Frappe / ERPNext sur Dokploy

Dépôt de déploiement d'une instance Frappe auto-hébergée. Il ne contient aucun code
applicatif : uniquement la définition de l'image Docker personnalisée et les fichiers
nécessaires au déploiement.

## Contenu

| Fichier | Rôle |
| --- | --- |
| `apps.json` | Liste des applications Frappe embarquées dans l'image |
| `.github/workflows/build-image.yml` | Construction et publication de l'image sur GitHub Container Registry |
| `docker-compose.yml` | Pile applicative destinée à un service Dokploy de type Docker Compose |
| `.env.example` | Modèle des variables à renseigner dans Dokploy |

## Cible

- Site unique : `erp.mowoapp.com`
- Image : `ghcr.io/maebaconsulting/frappe`
- Serveur Hetzner x86 sous Ubuntu 24.04, Dokploy et Traefik déjà en place
- DNS géré par Cloudflare

Applications installées sur le site :

| Application | Dépôt | Branche |
| --- | --- | --- |
| ERPNext | `frappe/erpnext` | `version-16` |
| Payments | `frappe/payments` | `version-16` |
| Frappe HR | `frappe/hrms` | `version-16` |
| Frappe CRM | `frappe/crm` | `main` |
| Frappe Builder | `frappe/builder` | `main` |
| Frappe Drive | `frappe/drive` | `main` |

## 1. Construction et publication de l'image

### Pourquoi la construction passe par GitHub Actions

La construction ne se fait pas en local. Le poste de travail est en Apple Silicon
(arm64) et la cible de production en amd64 : une construction locale passerait par
l'émulation QEMU, ce qui rend la compilation des interfaces Vue de CRM, Builder et
Drive interminable. Le workflow produit donc directement une image `linux/amd64`.

### Lancer une construction

Deux déclencheurs :

- manuellement, depuis l'onglet **Actions** du dépôt, workflow « Construction de
  l'image Frappe », bouton **Run workflow** ;
- automatiquement, à chaque modification de `apps.json` poussée sur `main`.

Deux paramètres sont disponibles au lancement manuel :

| Paramètre | Défaut | Usage |
| --- | --- | --- |
| `image_tag` | `version-16` | Tag de l'image publiée |
| `frappe_docker_ref` | `main` | Référence du dépôt `frappe/frappe_docker` servant de contexte de construction |

Chaque exécution publie deux tags :

- un tag mobile, par exemple `ghcr.io/maebaconsulting/frappe:version-16`, qui suit
  toujours la dernière construction ;
- un tag immuable horodaté, par exemple
  `ghcr.io/maebaconsulting/frappe:version-16-20260803-141205`, qui permet de revenir
  à une version antérieure depuis Dokploy.

Le récapitulatif du job affiche les deux valeurs.

Compter entre quarante minutes et un peu plus d'une heure pour la première
construction. Les suivantes sont plus rapides grâce au cache Buildx de type `gha`.
Le job est configuré avec un délai maximal de cent quatre-vingts minutes.

### Choix techniques du workflow

Le fichier `images/layered/Containerfile` du dépôt `frappe/frappe_docker` copie
`resources/core/main-entrypoint.sh` et `resources/core/start.sh`. Le contexte de
construction doit donc être la racine de `frappe_docker`, et non celle de ce dépôt.
Le workflow clone `frappe/frappe_docker` dans un sous-dossier et pointe l'`apps.json`
local par un chemin absolu.

`apps.json` est transmis en secret BuildKit, jamais en argument de construction. Un
argument de construction reste lisible en clair dans `docker image history`, ce qui
exposerait tout jeton d'accès si un dépôt privé venait à être ajouté à la liste.

Conséquence de ce choix : le contenu d'un secret BuildKit n'entre pas dans la clé de
cache des couches. Un `apps.json` modifié ne provoquerait donc aucune invalidation, et
Docker réutiliserait une couche périmée. Le workflow contourne cela avec l'argument
`CACHE_BUST`, câblé sur l'identifiant d'exécution GitHub : la couche `bench init` est
reconstruite à chaque exécution, ce qui récupère au passage les derniers commits des
branches suivies, tandis que les couches système coûteuses restent en cache.

### Visibilité du paquet publié

Un paquet GitHub Container Registry reste **privé par défaut**, même lorsque le dépôt
qui le produit est public. C'est le point de friction le plus fréquent au premier
déploiement.

Vérification, après la première construction réussie :

1. Ouvrir `https://github.com/orgs/maebaconsulting/packages` (ou l'onglet
   **Packages** du profil si le dépôt appartient à un compte personnel).
2. Ouvrir le paquet `frappe`, puis **Package settings**.
3. Section **Danger zone**, **Change package visibility**.

Deux cas de figure côté Dokploy :

**Paquet public.** Rien à configurer. Dokploy tire l'image sans authentification.

**Paquet privé.** Il faut déclarer les identifiants du registre dans Dokploy avant le
déploiement, sinon le tirage échoue avec une erreur `unauthorized` ou
`manifest unknown` :

1. Créer un jeton d'accès personnel GitHub avec le scope `read:packages`.
2. Dans Dokploy, section **Registry**, ajouter un registre :
   - URL : `ghcr.io`
   - nom d'utilisateur : votre identifiant GitHub
   - mot de passe : le jeton créé à l'étape précédente
3. Rattacher ce registre au service avant de déployer.

Dans le doute, tester depuis le serveur :

```bash
docker pull ghcr.io/maebaconsulting/frappe:version-16
```

## 2. Déploiement dans Dokploy

### Créer le service

Le service doit être de type **Docker Compose**, et non Docker Stack. La pile utilise
trois conteneurs éphémères, `configurator`, `create-site` et `migrator`, dont les
autres services dépendent par la condition `service_completed_successfully`. En mode Swarm, ces
conteneurs seraient redémarrés en boucle et la condition ne serait jamais satisfaite.

1. Créer un projet, puis un service de type **Compose**.
2. Source : **Git**, dépôt `https://github.com/maebaconsulting/frappe.git`, branche
   `main`.
3. Chemin du fichier Compose : `./docker-compose.yml`.

### Variables d'environnement

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

### Domaine et certificat

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

### Premier déploiement

Le conteneur `create-site` crée le site et installe les six applications. Compter
plusieurs minutes. Suivre sa sortie dans les journaux du service : c'est là
qu'apparaissent les erreurs de mot de passe de base de données ou de connexion.

La commande de création est idempotente. Si `sites/erp.mowoapp.com` existe déjà, le
conteneur sort en code 0 sans rien toucher, ce qui rend les redéploiements Dokploy
sans danger pour l'installation en place.

Le conteneur `migrator` prend ensuite le relais et applique `bench migrate`. Sur un
site fraîchement créé l'opération est brève. C'est seulement une fois qu'il s'est
terminé en code 0 que `backend`, `websocket`, `scheduler` et les deux files démarrent.

## 3. Réglages Cloudflare

C'est la principale source de faux problèmes. Les symptômes ressemblent à des pannes
de la pile Frappe alors que l'origine est dans la configuration du proxy.

### Émission du certificat

Laisser l'enregistrement A de `erp` en **DNS only** (nuage gris) le temps que Let's
Encrypt émette le certificat. Le défi HTTP-01 doit atteindre Traefik directement.
Une fois le certificat obtenu et le site accessible en HTTPS, activer le proxy
(nuage orange).

### Mode SSL/TLS

Obligatoirement **Full (strict)**.

En mode Flexible, Cloudflare parle en HTTP à l'origine alors que Frappe redirige vers
HTTPS. La redirection revient à Cloudflare, qui redemande en HTTP, et ainsi de suite :
le navigateur affiche une boucle de redirection. Le mode Full sans strict fonctionne
mais ne valide pas le certificat de l'origine, ce qui n'a aucun intérêt ici puisque
le certificat Let's Encrypt est valide.

### Plafond de taille des requêtes

Cent mégaoctets sur les plans Free et Pro, non contournable. Cela limite directement
les dépôts de fichiers dans Drive et les pièces jointes volumineuses. La variable
`CLIENT_MAX_BODY_SIZE` du service `frontend` est alignée sur cette valeur : la
remonter n'aurait aucun effet tant que le trafic passe par le proxy Cloudflare.

Pour déposer un fichier plus gros, passer temporairement l'enregistrement en DNS only,
ou copier le fichier sur le serveur puis l'importer en ligne de commande.

### Délai d'attente de cent secondes

Cloudflare coupe la connexion au bout de cent secondes et renvoie une erreur 524. Les
imports de données volumineux et les sauvegardes complètes dépassent régulièrement ce
délai. Ces opérations se lancent en SSH avec `bench`, pas depuis l'interface web.

### Rocket Loader et obfuscation des adresses e-mail

Les deux doivent être **désactivés** sur ce domaine. Ils injectent du JavaScript dans
les pages servies, ce qui casse le desk Frappe : champs qui ne se remplissent pas,
formulaires figés, erreurs JavaScript en console.

- Rocket Loader : **Speed**, puis **Optimization**.
- Email Address Obfuscation : **Scrape Shield**.

Si d'autres domaines de la zone ont besoin de ces fonctions, les désactiver
uniquement sur `erp.mowoapp.com` au moyen d'une règle de configuration
(**Rules**, puis **Configuration Rules**).

## 4. URL d'accès

| Interface | URL |
| --- | --- |
| Desk ERPNext | `https://erp.mowoapp.com/app` |
| Administration RH | `https://erp.mowoapp.com/app/hr` |
| Espace collaborateur RH | `https://erp.mowoapp.com/hr` |
| CRM | `https://erp.mowoapp.com/crm` |
| Builder | `https://erp.mowoapp.com/builder` |
| Drive | `https://erp.mowoapp.com/drive` |

Connexion initiale : utilisateur `Administrator`, mot de passe celui de la variable
`ADMIN_PASSWORD`.

## 5. Mise à jour de l'image

### Pourquoi une migration est nécessaire

Dans Frappe, le schéma de la base n'existe pas seulement dans la base. Chaque DocType
est défini par un fichier JSON embarqué dans le code de l'application, et la table SQL
correspondante en est dérivée. Le code et la base sont donc deux copies de la même
vérité.

Une nouvelle image apporte de nouveaux commits d'ERPNext, HR, CRM, Builder et Drive,
donc potentiellement de nouveaux champs, de nouveaux DocTypes, des index modifiés. La
base, elle, vit dans le volume `db-data` et n'en sait rien. `bench migrate` remet les
deux en phase : synchronisation du schéma, exécution des patchs de données listés
dans le `patches.txt` de chaque application, synchronisation des fixtures et des
rapports standard, reconstruction du cache et de l'index de recherche.

Sans cette étape, les symptômes sont déroutants : un formulaire qui refuse
d'enregistrer sur un champ absent en base, un rapport qui plante, ou un site qui ne
démarre pas du tout.

### Le service migrator

La migration est automatique. Le service `migrator` du fichier Compose s'exécute à
chaque démarrage de la pile, applique `bench migrate` puis se termine. Il est adapté
de `overrides/compose.migrator.yaml` du dépôt `frappe_docker`, avec trois différences
assumées.

Il attend la fin de `create-site` et pas seulement celle de `configurator`. Sans cela,
rien ne garantirait au premier déploiement qu'il ne se lance pas pendant la création
du site.

`backend`, `websocket`, `scheduler` et les deux files de traitement dépendent de sa
réussite, au lieu de dépendre de `configurator`. Sans cela ils démarreraient en
parallèle de la migration et serviraient des requêtes sur une base pas encore alignée
sur le code.

Sa politique de redémarrage est `no` et non `on-failure:5`. Puisque les services de
longue durée dépendent désormais de sa réussite, un échec doit se voir franchement
plutôt qu'être rejoué cinq fois sur une base à moitié migrée. Un `bench migrate` qui
échoue est presque toujours un vrai problème, pas un aléa.

Conséquence à connaître : chaque redéploiement comporte une courte interruption, le
temps de la migration. Elle est de quelques secondes quand il n'y a rien à migrer, de
plusieurs minutes après un saut de version important.

### Séquence de mise à jour

1. Relancer le workflow depuis l'onglet Actions.
2. Prendre une sauvegarde : voir la section 6.
3. Redéployer le service dans Dokploy. Les services utilisent `pull_policy: always`,
   la nouvelle image est donc tirée même à tag identique. Le `migrator` applique la
   migration au démarrage.
4. Suivre les journaux du service `migrator`. Les lignes utiles sont préfixées par
   `[migrator]`.

### Migrer à la main

L'interrupteur `MIGRATE_SITES` permet de déployer une image sans migrer, par exemple
pour prendre une sauvegarde entre les deux opérations. Le passer à `false`, redéployer,
puis :

```bash
# Identifier le conteneur backend
docker ps --format '{{.Names}}' | grep backend

# Migrer le site
docker exec <nom-du-conteneur-backend> bench --site erp.mowoapp.com migrate
```

Ne pas oublier de le repasser à `true` ensuite.

### Retour arrière

Renseigner un tag horodaté dans `ERP_IMAGE`, par exemple
`ghcr.io/maebaconsulting/frappe:version-16-20260803-141205`, puis redéployer.

Attention : un retour arrière d'image ne défait pas une migration déjà appliquée. Le
schéma reste celui de la nouvelle version, que l'ancien code ne sait pas lire. Un vrai
retour arrière passe donc par une restauration de sauvegarde. C'est la raison d'être
de l'étape 2 de la séquence ci-dessus.

## 6. Sauvegarde

### Pourquoi les sauvegardes Dokploy ne suffisent pas

Les sauvegardes automatiques de Dokploy ciblent les bases de données que Dokploy
gère lui-même, déclarées comme services de type base de données. Ici, MariaDB est
déclarée dans le fichier Compose : Dokploy ne la voit pas et ne la sauvegardera
jamais. Il faut mettre en place une sauvegarde applicative.

### Tâche planifiée

`bench backup --with-files` produit trois archives dans
`sites/erp.mowoapp.com/private/backups` : le dump SQL, les fichiers publics et les
fichiers privés.

Script à placer sur le serveur, par exemple `/usr/local/bin/frappe-backup.sh` :

```bash
#!/bin/bash
set -euo pipefail

SITE="erp.mowoapp.com"
DESTINATION="/var/backups/frappe"

CONTENEUR="$(docker ps --format '{{.Names}}' | grep -m1 -- '-backend-')"
if [ -z "$CONTENEUR" ]; then
  echo "Conteneur backend introuvable" >&2
  exit 1
fi

docker exec "$CONTENEUR" bench --site "$SITE" backup --with-files

mkdir -p "$DESTINATION"
docker cp "$CONTENEUR:/home/frappe/frappe-bench/sites/$SITE/private/backups/." "$DESTINATION/"

# Ne garder que les trente derniers jours en local
find "$DESTINATION" -type f -mtime +30 -delete
```

Rendre le script exécutable, puis l'ajouter à la crontab de root :

```bash
chmod +x /usr/local/bin/frappe-backup.sh
crontab -e
```

```txt
30 2 * * * /usr/local/bin/frappe-backup.sh >> /var/log/frappe-backup.log 2>&1
```

Une sauvegarde complète peut dépasser les cent secondes de Cloudflare, d'où le
lancement en SSH et non depuis l'interface web.

### Export hors du serveur

Une sauvegarde qui reste sur la machine sauvegardée ne protège de rien. Copier les
archives vers un stockage externe, par exemple avec `rclone` vers un espace objet :

```bash
rclone sync /var/backups/frappe distant:sauvegardes/erp-mowoapp --transfers 2
```

À ajouter en fin de script de sauvegarde, ou en tâche planifiée distincte un peu plus
tard dans la nuit.

### Restauration

```bash
docker exec -it <nom-du-conteneur-backend> bench --site erp.mowoapp.com restore \
  /home/frappe/frappe-bench/sites/erp.mowoapp.com/private/backups/<archive>.sql.gz \
  --with-public-files <archive>-files.tar \
  --with-private-files <archive>-private-files.tar \
  --db-root-username root \
  --db-root-password "$DB_ROOT_PASSWORD"
```

Tester la procédure de restauration au moins une fois avant d'en avoir besoin.

## 7. Dépannage

**« Site not found ».** `FRAPPE_SITE_NAME_HEADER` diverge du nom réel du site.
Vérifier que le dossier existe :

```bash
docker exec <backend> ls sites/
```

Le nom affiché doit être exactement la valeur de `SITE_NAME` et du domaine Traefik.

**Boucle de redirection.** Mode SSL/TLS Cloudflare en Flexible. Passer en Full (strict).

**Erreur 524 sur un import ou une sauvegarde.** Délai Cloudflare de cent secondes.
Lancer l'opération en SSH avec `bench`.

**Dépôt de fichier refusé au-delà de cent mégaoctets.** Plafond Cloudflare des plans
Free et Pro.

**Desk Frappe qui ne réagit plus, erreurs JavaScript.** Rocket Loader ou l'obfuscation
des adresses e-mail est resté actif.

**Échec du tirage de l'image.** Le paquet ghcr est privé. Le rendre public, ou
déclarer les identifiants du registre dans Dokploy.

**`migrator` en échec, la pile ne démarre pas.** `backend` et les workers attendent sa
réussite. Lire ses journaux : un patch en erreur y apparaît avec sa trace Python. Pour
remettre le service debout sans migrer, passer `MIGRATE_SITES` à `false` et
redéployer, puis traiter la migration à la main sur une base sauvegardée.

**`create-site` en échec.** Consulter ses journaux. Les causes fréquentes sont un
`DB_ROOT_PASSWORD` qui ne correspond pas à celui reçu par le conteneur `db` lors de
la première initialisation du volume, ou un volume `db-data` déjà initialisé avec un
autre mot de passe. Dans ce dernier cas, le mot de passe stocké dans le volume prime
sur la variable d'environnement.

## Références

- Dépôt de référence : `https://github.com/frappe/frappe_docker`
- Fichier de référence de la pile : `pwd.yml`
- Documentation de construction : `docs/02-setup/02-build-setup.md`
- Construction automatisée et cache : `docs/03-production/06-automated-builds-and-deployment.md`
