# Frappe / ERPNext sur Dokploy

Dépôt de déploiement d'une instance Frappe auto-hébergée. Il ne contient aucun code
applicatif : uniquement la définition de l'image Docker personnalisée, les fichiers de
déploiement et la documentation d'exploitation.

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
| Frappe Builder | `frappe/builder` | `master` |
| Frappe Drive | `frappe/drive` | `develop` |

Ces branches ne sont pas interchangeables et deux d'entre elles ne suivent pas la
convention attendue. Elles ont été retenues sur constat, pas par convention.

**Frappe Builder n'a pas de branche `main`.** Sa branche de publication est `master`,
celle que cible la version v1.32.0. Une branche inexistante fait échouer le
`bench init` sur un `Remote branch not found`, après plusieurs minutes de
construction. C'est précisément ce que détecte le contrôle préalable du workflow.

**Frappe Drive est suivi sur `develop` et non sur `main`.** Sur `main`, le script de
post-installation appelle `pnpm install` derrière une garde qui n'installe pnpm 10 que
si aucun `pnpm` n'est déjà présent. Or l'image de construction de Frappe fournit un
shim corepack : la garde considère pnpm présent, saute l'épinglage, et corepack résout
`latest`, soit pnpm 11. Cette version transforme en erreur fatale l'avertissement
`ERR_PNPM_IGNORED_BUILDS` et la construction s'arrête. La branche `develop` compile son
frontend avec yarn, sans pnpm, et n'est pas concernée. C'est aussi la branche active du
dépôt, en avance de 249 commits sur `main`, et celle dont a été publiée la v0.3.0.

## Contenu du dépôt

| Chemin | Rôle |
| --- | --- |
| `apps.json` | Liste des applications Frappe embarquées dans l'image |
| `.github/workflows/build-image.yml` | Construction et publication de l'image sur GitHub Container Registry |
| `.github/scripts/verifier-apps.py` | Contrôle préalable de `apps.json` et de l'existence des branches |
| `docker-compose.yml` | Pile applicative destinée à un service Dokploy de type Docker Compose |
| `.env.example` | Modèle des variables à renseigner dans Dokploy |
| `scripts/frappe-backup.sh` | Sauvegarde applicative, base et fichiers, à planifier sur le serveur |
| `docs/` | Documentation d'exploitation, un fichier par thème |

## Documentation

| Document | Sujet |
| --- | --- |
| [Construction et publication de l'image](docs/01-image.md) | Lancer le workflow, tags produits, choix techniques, visibilité du paquet |
| [Déploiement dans Dokploy](docs/02-dokploy.md) | Service Compose, variables, domaine et port, premier déploiement |
| [Réglages Cloudflare](docs/03-cloudflare.md) | DNS, certificat Let's Encrypt, conséquences du proxy |
| [URL d'accès aux interfaces](docs/04-acces.md) | Chemins relevés sur l'instance, connexion initiale |
| [Mise à jour de l'image](docs/05-mise-a-jour.md) | Migration automatique, service migrator, retour arrière |
| [Sauvegarde et restauration](docs/06-sauvegarde.md) | Script, tâche planifiée, export hors serveur, restauration |
| [Dépannage](docs/07-depannage.md) | Symptômes courants et leur cause réelle |

## Démarrage rapide

Pour une instance à créer de zéro, dans cet ordre :

1. Lancer le workflow **Construction de l'image Frappe** depuis l'onglet Actions, puis
   vérifier que le paquet publié est accessible. Voir
   [la documentation de l'image](docs/01-image.md).
2. Vérifier que le domaine résout vers le serveur et reste en **DNS only** le temps de
   l'émission du certificat. Voir [les réglages Cloudflare](docs/03-cloudflare.md).
3. Créer le service Dokploy de type **Compose**, saisir les variables, rattacher le
   domaine au service `frontend` sur le port `8080`, puis déployer. Voir
   [le déploiement](docs/02-dokploy.md).
4. Installer et planifier la sauvegarde. Rien n'est sauvegardé tant que ce n'est pas
   fait. Voir [la sauvegarde](docs/06-sauvegarde.md).

## Références

- Dépôt de référence : `https://github.com/frappe/frappe_docker`
- Fichier de référence de la pile : `pwd.yml`
- Documentation de construction : `docs/02-setup/02-build-setup.md`
- Construction automatisée et cache : `docs/03-production/06-automated-builds-and-deployment.md`
