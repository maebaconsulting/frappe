# Réglages Cloudflare

DNS, émission du certificat, et ce que change le passage derrière le proxy.

C'est la principale source de faux problèmes. Les symptômes ressemblent à des pannes
de la pile Frappe alors que l'origine est dans la configuration du proxy.

## Le certificat est géré par Dokploy

Aucune intervention sur le serveur. Dokploy embarque Traefik, et le champ
**Certificate : Let's Encrypt** du domaine déclenche la demande, l'installation et le
renouvellement automatique.

Deux conditions doivent être réunies au moment de la déclaration du domaine : le nom
doit résoudre vers l'IP du serveur, et le port 80 doit être joignable depuis
l'extérieur pour le défi HTTP-01. Contrôle depuis n'importe quelle machine :

```bash
dig +short erp.mowoapp.com A          # doit renvoyer l'IP du serveur
curl -o /dev/null -w '%{http_code}\n' http://erp.mowoapp.com/
```

Un code 404 sur le second appel est un bon résultat avant déploiement : il prouve que
Traefik répond, et signale seulement qu'aucune route ne correspond encore au domaine.
De même, un certificat `CN = TRAEFIK DEFAULT CERT` en HTTPS est le certificat de repli
auto-signé de Traefik, remplacé dès que le domaine est déclaré.

## Enregistrement DNS

La zone `mowoapp.com` porte un enregistrement joker `*.mowoapp.com` de type A, en
**DNS only**. Il couvre `erp.mowoapp.com` sans qu'aucun enregistrement dédié soit
nécessaire, et son état non proxifié est exactement celui qu'exige l'émission du
certificat.

## Proxifier, ou non

Tant que l'enregistrement reste en **DNS only**, le trafic va directement à Traefik et
rien de ce qui suit dans cette section ne s'applique : ni le plafond de 100 Mo, ni le
délai de 100 secondes, ni Rocket Loader. En contrepartie, l'adresse IP du serveur est
publique et il n'y a ni filtrage ni cache en amont.

Pour passer derrière le proxy, ne pas orangir le joker sans y avoir réfléchi : la
bascule porterait sur tous les sous-domaines de la zone, existants et futurs. En DNS,
un enregistrement explicite l'emporte sur le joker. La bonne granularité s'obtient donc
en créant un enregistrement A dédié `erp` vers la même adresse et en proxifiant
celui-là seul, le joker restant gris.

Ne le faire qu'une fois le certificat Let's Encrypt émis et le site accessible en
HTTPS. Activer le proxy avant l'émission empêche le défi HTTP-01 d'aboutir et superpose
deux problèmes au lieu d'un.

Les réglages ci-dessous ne concernent que le cas proxifié.

## Mode SSL/TLS

Obligatoirement **Full (strict)**.

En mode Flexible, Cloudflare parle en HTTP à l'origine alors que Frappe redirige vers
HTTPS. La redirection revient à Cloudflare, qui redemande en HTTP, et ainsi de suite :
le navigateur affiche une boucle de redirection. Le mode Full sans strict fonctionne
mais ne valide pas le certificat de l'origine, ce qui n'a aucun intérêt ici puisque
le certificat Let's Encrypt est valide.

## Plafond de taille des requêtes

Cent mégaoctets sur les plans Free et Pro, non contournable. Cela limite directement
les dépôts de fichiers dans Drive et les pièces jointes volumineuses. La variable
`CLIENT_MAX_BODY_SIZE` du service `frontend` est alignée sur cette valeur : la
remonter n'aurait aucun effet tant que le trafic passe par le proxy Cloudflare.

Pour déposer un fichier plus gros, passer temporairement l'enregistrement en DNS only,
ou copier le fichier sur le serveur puis l'importer en ligne de commande.

## Délai d'attente de cent secondes

Cloudflare coupe la connexion au bout de cent secondes et renvoie une erreur 524. Les
imports de données volumineux et les sauvegardes complètes dépassent régulièrement ce
délai. Ces opérations se lancent en SSH avec `bench`, pas depuis l'interface web.

## Rocket Loader et obfuscation des adresses e-mail

Les deux doivent être **désactivés** sur ce domaine. Ils injectent du JavaScript dans
les pages servies, ce qui casse le desk Frappe : champs qui ne se remplissent pas,
formulaires figés, erreurs JavaScript en console.

- Rocket Loader : **Speed**, puis **Optimization**.
- Email Address Obfuscation : **Scrape Shield**.

Si d'autres domaines de la zone ont besoin de ces fonctions, les désactiver
uniquement sur `erp.mowoapp.com` au moyen d'une règle de configuration
(**Rules**, puis **Configuration Rules**).

[← Déploiement dans Dokploy](02-dokploy.md) · [Index](../README.md) · [URL d'accès aux interfaces →](04-acces.md)
