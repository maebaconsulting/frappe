#!/usr/bin/env bash
# Sauvegarde de l'instance Frappe déployée par Dokploy.
#
# Les sauvegardes automatiques de Dokploy ne voient pas cette base : MariaDB est
# déclarée dans le fichier Compose et n'est pas un service géré par Dokploy. Ce
# script produit donc une sauvegarde applicative complète, base et fichiers, la
# sort du conteneur et la dépose sur l'hôte.
#
# Ordre volontaire des opérations : produire, copier, vérifier, puis seulement
# purger. Aucune suppression n'a lieu tant qu'une copie vérifiée n'existe pas.
#
# Usage :
#   ./frappe-backup.sh
#   SITE=autre.example.com DESTINATION=/mnt/sauvegardes ./frappe-backup.sh
#   RCLONE_REMOTE=distant:sauvegardes/erp ./frappe-backup.sh

set -euo pipefail

SITE="${SITE:-erp.mowoapp.com}"
DESTINATION="${DESTINATION:-/var/backups/frappe}"
MOTIF_CONTENEUR="${MOTIF_CONTENEUR:--backend-}"

# Rétention des archives sur l'hôte, en jours.
RETENTION_HOTE="${RETENTION_HOTE:-30}"

# Rétention à l'intérieur du volume sites, en jours. Sans purge, le volume
# grossit indéfiniment. Mettre 0 pour ne rien supprimer dans le conteneur.
RETENTION_CONTENEUR="${RETENTION_CONTENEUR:-7}"

# Export hors du serveur. Vide, l'étape est ignorée.
RCLONE_REMOTE="${RCLONE_REMOTE:-}"

VERROU="${VERROU:-/var/lock/frappe-backup.lock}"

journal() {
  printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

erreur() {
  printf '%s  ERREUR : %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
  exit 1
}

# Un seul exemplaire à la fois : une sauvegarde longue ne doit pas croiser la
# suivante lancée par la tâche planifiée.
exec 9>"$VERROU"
if ! flock -n 9; then
  journal "Une sauvegarde est déjà en cours, abandon."
  exit 0
fi

command -v docker >/dev/null 2>&1 || erreur "docker est introuvable"

# Le nom du conteneur est engendré par Dokploy et change si le service est
# recréé. On le résout à chaque exécution plutôt que de le figer.
mapfile -t conteneurs < <(
  docker ps --filter "status=running" --format '{{.Names}}' | grep -- "$MOTIF_CONTENEUR" || true
)

if [ "${#conteneurs[@]}" -eq 0 ]; then
  erreur "aucun conteneur en marche ne correspond au motif '$MOTIF_CONTENEUR'"
fi
if [ "${#conteneurs[@]}" -gt 1 ]; then
  erreur "plusieurs conteneurs correspondent au motif '$MOTIF_CONTENEUR' : ${conteneurs[*]}"
fi

CONTENEUR="${conteneurs[0]}"
journal "Conteneur retenu : $CONTENEUR"

DOSSIER_DISTANT="sites/$SITE/private/backups"

if ! docker exec "$CONTENEUR" test -d "sites/$SITE"; then
  erreur "le site $SITE n'existe pas dans $CONTENEUR"
fi

# Horloge du conteneur et non celle de l'hôte : le find qui suit s'exécute à
# l'intérieur, un décalage produirait une liste incomplète ou trop large.
repere=$(docker exec "$CONTENEUR" date +%s)

journal "Sauvegarde de $SITE, base et fichiers"
docker exec "$CONTENEUR" bench --site "$SITE" backup --with-files

mapfile -t archives < <(
  docker exec "$CONTENEUR" \
    find "$DOSSIER_DISTANT" -type f -newermt "@$repere" | sort
)

if [ "${#archives[@]}" -eq 0 ]; then
  erreur "bench n'a produit aucun fichier dans $DOSSIER_DISTANT"
fi
journal "${#archives[@]} fichiers produits"

mkdir -p "$DESTINATION"

copies=()
for archive in "${archives[@]}"; do
  nom=$(basename "$archive")
  cible="$DESTINATION/$nom"

  docker cp "$CONTENEUR:/home/frappe/frappe-bench/$archive" "$cible"

  # Vérification par la taille : une copie tronquée par un disque plein doit
  # interdire la purge qui suit.
  taille_source=$(docker exec "$CONTENEUR" stat -c %s "$archive")
  taille_cible=$(stat -c %s "$cible" 2>/dev/null || stat -f %z "$cible")

  if [ "$taille_source" != "$taille_cible" ]; then
    erreur "copie incohérente pour $nom : $taille_source octets en source, $taille_cible à l'arrivée"
  fi

  journal "  $nom  ($taille_cible octets)  vérifié"
  copies+=("$cible")
done

if [ -n "$RCLONE_REMOTE" ]; then
  if command -v rclone >/dev/null 2>&1; then
    journal "Export vers $RCLONE_REMOTE"
    rclone copy "$DESTINATION" "$RCLONE_REMOTE" --transfers 2 --checksum
    journal "Export terminé"
  else
    journal "AVERTISSEMENT : RCLONE_REMOTE est défini mais rclone est absent, export ignoré"
  fi
fi

# Purges seulement maintenant, une fois les copies vérifiées et exportées.
if [ "$RETENTION_CONTENEUR" -gt 0 ]; then
  journal "Purge dans le conteneur des archives de plus de $RETENTION_CONTENEUR jours"
  docker exec "$CONTENEUR" \
    find "$DOSSIER_DISTANT" -type f -mtime "+$RETENTION_CONTENEUR" -delete
fi

if [ "$RETENTION_HOTE" -gt 0 ]; then
  journal "Purge sur l'hôte des archives de plus de $RETENTION_HOTE jours"
  find "$DESTINATION" -type f -mtime "+$RETENTION_HOTE" -delete
fi

journal "Sauvegarde terminée, ${#copies[@]} fichiers dans $DESTINATION"
