#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Contrôle préalable de apps.json.

Valide la structure du fichier, puis vérifie que chaque branche déclarée existe
réellement dans le dépôt distant. Sans ce contrôle, une branche inexistante ne
se révèle qu'au bout de plusieurs minutes de construction, lorsque le bench init
échoue sur un « Remote branch not found ».
"""

import json
import subprocess
import sys
from pathlib import Path

CHEMIN = Path(__file__).resolve().parents[2] / "apps.json"


def charger():
    """Charge apps.json et valide sa structure."""
    donnees = json.loads(CHEMIN.read_text(encoding="utf-8"))
    if not isinstance(donnees, list) or not donnees:
        raise SystemExit("apps.json doit être une liste non vide")
    for entree in donnees:
        if not isinstance(entree, dict):
            raise SystemExit(f"Entrée invalide, objet attendu : {entree!r}")
        manquantes = {"url", "branch"} - set(entree)
        if manquantes:
            raise SystemExit(f"Clés manquantes {sorted(manquantes)} dans {entree!r}")
    return donnees


def branche_existe(url, branche):
    """Interroge le dépôt distant sans le cloner."""
    resultat = subprocess.run(
        ["git", "ls-remote", "--heads", url, branche],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if resultat.returncode != 0:
        return False, resultat.stderr.strip() or "dépôt injoignable"
    if not resultat.stdout.strip():
        return False, "branche inexistante"
    return True, resultat.stdout.split()[0][:12]


def main():
    applications = charger()
    echecs = []

    for entree in applications:
        url, branche = entree["url"], entree["branch"]
        nom = url.rstrip("/").split("/")[-1]
        ok, detail = branche_existe(url, branche)
        etat = "OK" if ok else "ECHEC"
        print(f"{etat:6s} {nom:12s} {branche:12s} {detail}", flush=True)
        if not ok:
            echecs.append(f"{url} branche {branche} : {detail}")

    if echecs:
        print("\nBranches introuvables :", file=sys.stderr)
        for ligne in echecs:
            print(f"  - {ligne}", file=sys.stderr)
        print(
            "\nCorriger apps.json avant de relancer. La branche de publication "
            "n'est pas toujours main : Frappe Builder publie depuis master.",
            file=sys.stderr,
        )
        return 1

    print(f"\n{len(applications)} applications validées.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
