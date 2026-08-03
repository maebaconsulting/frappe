# Construction et publication de l'image

Construire l'image personnalisée dans GitHub Actions et la publier sur GitHub Container Registry.

## Pourquoi la construction passe par GitHub Actions

La construction ne se fait pas en local. Le poste de travail est en Apple Silicon
(arm64) et la cible de production en amd64 : une construction locale passerait par
l'émulation QEMU, ce qui rend la compilation des interfaces Vue de CRM, Builder et
Drive interminable. Le workflow produit donc directement une image `linux/amd64`.

## Lancer une construction

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

## Choix techniques du workflow

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

## Visibilité du paquet publié

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

[Index](../README.md) · [Déploiement dans Dokploy →](02-dokploy.md)
