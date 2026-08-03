# Sauvegarde et restauration

Le script, sa mise en place, la tâche planifiée, l'export hors serveur.

## Pourquoi les sauvegardes Dokploy ne suffisent pas

Les sauvegardes automatiques de Dokploy ciblent les bases de données que Dokploy gère
lui-même, déclarées comme services de type base de données. Ici MariaDB est déclarée
dans le fichier Compose : Dokploy ne la voit pas et ne la sauvegardera jamais. Sans la
mise en place ci-dessous, **rien n'est sauvegardé**.

## Le script

`scripts/frappe-backup.sh` produit une sauvegarde applicative complète, base et
fichiers, la sort du conteneur et la dépose sur l'hôte.

Il enchaîne : résolution du nom du conteneur backend, `bench backup --with-files`,
copie des seules archives produites par cette exécution, **vérification de la taille de
chaque copie**, export optionnel hors du serveur, puis purge des anciennes archives.

Cet ordre est délibéré. La séquence naïve, sauvegarder puis purger, détruit les
archives antérieures le jour où le disque de destination est plein : la nouvelle copie
est tronquée, la purge s'exécute quand même, et il ne reste qu'une sauvegarde
inutilisable. Ici aucune suppression n'a lieu tant qu'une copie vérifiée n'existe pas.

Le script se règle par variables d'environnement, toutes optionnelles :

| Variable | Défaut | Rôle |
| --- | --- | --- |
| `SITE` | `erp.mowoapp.com` | Site à sauvegarder |
| `DESTINATION` | `/var/backups/frappe` | Dossier de dépôt sur l'hôte |
| `RETENTION_HOTE` | `30` | Jours de conservation sur l'hôte, 0 pour ne rien purger |
| `RETENTION_CONTENEUR` | `7` | Jours de conservation dans le volume `sites`, 0 pour ne rien purger |
| `RCLONE_REMOTE` | vide | Destination `rclone` pour l'export hors serveur |
| `MOTIF_CONTENEUR` | `-backend-` | Motif de résolution du conteneur backend |

Le nom du conteneur n'est pas figé : il est engendré par Dokploy et change si le
service est recréé. Le script le résout à chaque exécution et refuse de continuer si
le motif correspond à zéro ou à plusieurs conteneurs, plutôt que d'en choisir un au
hasard.

## Installation sur le serveur

```bash
sudo git clone https://github.com/maebaconsulting/frappe.git /opt/frappe-deploy
sudo chmod +x /opt/frappe-deploy/scripts/frappe-backup.sh
```

Premier essai à la main, avant toute planification :

```bash
sudo /opt/frappe-deploy/scripts/frappe-backup.sh
```

La sortie doit se terminer par une ligne `Sauvegarde terminée` et trois fichiers doivent
apparaître dans `/var/backups/frappe` : le dump SQL en `.sql.gz`, les fichiers publics
et les fichiers privés en `.tar`.

## Tâche planifiée

```bash
sudo crontab -e
```

```txt
30 2 * * * /opt/frappe-deploy/scripts/frappe-backup.sh >> /var/log/frappe-backup.log 2>&1
```

Une sauvegarde complète peut dépasser les cent secondes de délai de Cloudflare, d'où le
lancement par cron et non depuis une interface web.

Le script pose un verrou avec `flock` : si une sauvegarde déborde sur l'heure de la
suivante, la seconde renonce proprement au lieu de s'exécuter en parallèle.

Pour mettre le script à jour après une modification dans ce dépôt :

```bash
sudo git -C /opt/frappe-deploy pull
```

## Export hors du serveur

Une sauvegarde qui reste sur la machine sauvegardée ne protège de rien. Configurer
`rclone` vers un stockage objet, puis renseigner la variable dans la tâche planifiée :

```txt
30 2 * * * RCLONE_REMOTE=distant:sauvegardes/erp-mowoapp /opt/frappe-deploy/scripts/frappe-backup.sh >> /var/log/frappe-backup.log 2>&1
```

L'export a lieu **avant** les purges. Un `rclone` en échec interrompt donc le script et
laisse les archives en place.

## Restauration

```bash
CONTENEUR=$(docker ps --format '{{.Names}}' | grep -m1 -- '-backend-')
docker exec -it "$CONTENEUR" bench --site erp.mowoapp.com restore \
  /home/frappe/frappe-bench/sites/erp.mowoapp.com/private/backups/<archive>.sql.gz \
  --with-public-files <archive>-files.tar \
  --with-private-files <archive>-private-files.tar \
  --db-root-username root \
  --db-root-password "$DB_ROOT_PASSWORD"
```

Si les archives ne sont plus dans le conteneur parce que la purge est passée, les y
remettre d'abord :

```bash
docker cp /var/backups/frappe/<archive>.sql.gz \
  "$CONTENEUR:/home/frappe/frappe-bench/sites/erp.mowoapp.com/private/backups/"
```

Tester la procédure de restauration au moins une fois avant d'en avoir besoin.

[← Mise à jour de l'image](05-mise-a-jour.md) · [Index](../README.md) · [Dépannage →](07-depannage.md)
