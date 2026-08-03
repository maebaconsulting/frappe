# URL d'accès aux interfaces

Chemins relevés sur l'instance en fonctionnement, et connexion initiale.

Chemins relevés sur l'instance en fonctionnement, pas déduits de la documentation.

| Interface | URL | Remarque |
| --- | --- | --- |
| Desk ERPNext | `https://erp.mowoapp.com/desk` | `/app` y redirige en 301 |
| Administration RH | `https://erp.mowoapp.com/desk/hr` | `/app/hr` y redirige en 301 |
| Espace collaborateur RH | `https://erp.mowoapp.com/hrms` | `/hr` seul renvoie un 404 |
| CRM | `https://erp.mowoapp.com/crm` | 403 tant que la session n'est pas ouverte |
| Builder | `https://erp.mowoapp.com/builder` | |
| Drive | `https://erp.mowoapp.com/drive` | |

Deux pièges de navigation valent d'être notés. Frappe 16 a déplacé le desk de `/app`
vers `/desk` : l'ancien chemin fonctionne toujours par redirection, mais les liens
durables gagnent à pointer sur `/desk`. Et l'espace collaborateur RH répond sur
`/hrms`, alors que `/hr` seul renvoie un 404 alors même que ses sous-routes comme
`/hr/dashboard` répondent normalement.

Connexion initiale : utilisateur `Administrator`, mot de passe celui de la variable
`ADMIN_PASSWORD`. Le champ du formulaire s'intitule « Courriel » mais accepte le nom
d'utilisateur.

Le service redirige HTTP vers HTTPS en 301. Un navigateur affichant « Non sécurisé »
sur ce domaine est resté sur une page HTTP en cache : un rechargement forcé suffit.

[← Réglages Cloudflare](03-cloudflare.md) · [Index](../README.md) · [Mise à jour de l'image →](05-mise-a-jour.md)
