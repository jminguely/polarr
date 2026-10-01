#!/bin/bash

# Activer l'environnement virtuel
source .venv/bin/activate

# Charger les variables d'environnement depuis le fichier .env
export $(grep -v '^#' .env | xargs)

# Lancer le serveur local FastAPI
echo "🚀 Démarrage de Polarr sur http://127.0.0.1:8080..."
uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
