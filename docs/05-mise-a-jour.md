# Mise à jour de l'image

Pourquoi une migration est nécessaire, le service migrator, et le retour arrière.

## Pourquoi une migration est nécessaire

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

## Le service migrator

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

## Séquence de mise à jour

1. Relancer le workflow depuis l'onglet Actions.
2. Prendre une sauvegarde, voir [Sauvegarde et restauration](06-sauvegarde.md).
3. Redéployer le service dans Dokploy. Les services utilisent `pull_policy: always`,
   la nouvelle image est donc tirée même à tag identique. Le `migrator` applique la
   migration au démarrage.
4. Suivre les journaux du service `migrator`. Les lignes utiles sont préfixées par
   `[migrator]`.

## Migrer à la main

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

## Retour arrière

Renseigner un tag horodaté dans `ERP_IMAGE`, par exemple
`ghcr.io/maebaconsulting/frappe:version-16-20260803-141205`, puis redéployer.

Attention : un retour arrière d'image ne défait pas une migration déjà appliquée. Le
schéma reste celui de la nouvelle version, que l'ancien code ne sait pas lire. Un vrai
retour arrière passe donc par une restauration de sauvegarde. C'est la raison d'être
de l'étape 2 de la séquence de mise à jour.

[← URL d'accès aux interfaces](04-acces.md) · [Index](../README.md) · [Sauvegarde et restauration →](06-sauvegarde.md)
