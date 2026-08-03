# Dépannage

Symptômes courants et leur cause réelle.

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

[← Sauvegarde et restauration](06-sauvegarde.md) · [Index](../README.md)
