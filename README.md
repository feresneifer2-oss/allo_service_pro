# Allo Service Pro

Application Flutter de mise en relation entre clients et prestataires de services en Tunisie.

## Fonctionnalités actuelles

- Parcours client et prestataire
- Français et arabe avec prise en charge RTL
- Catalogue et recherche de services
- Profils et filtres des prestataires
- Réservations et demandes de service
- Suivi des statuts, chat local et évaluations
- Inscription prestataire et tableau de bord
- Support et tableau de bord administrateur

## État technique

L'application utilise une architecture **local-first** : les données sont mises en cache localement avec `shared_preferences` et un **FIFO offline queue** (persisté sur disque) pour assurer une expérience sans interruption. Une passerelle Supabase est utilisée pour le backend (Postgres, Auth, Storage, Realtime).

### Stack technique

- **Frontend** : Flutter (Dart 3) + RTL (francais & arabe)
- **Backend** : Supabase (PostgreSQL + Auth + Storage + Realtime)
- **Notifications push** : OneSignal (avec Firebase Cloud Messaging sous le capot)
- **Stockage local** : SharedPreferences + offline FIFO queue
- **Gestion des identifiants** : `.env` (gitignored) + `--dart-define`

### Fonctionnalités clés récentes

- **Chat Media Privé avec Signed URLs** : Les médias de chat (photos/voix) sont stockés dans un bucket privé. Les URLs signées (expire 1h) sont générées côté client pour les afficher.
- **Notifications push** : Intégration OneSignal avec `login(userId)` sur session, `player_id` synced en base, `requestPermission()` sur l'ouverture de l'app.
- **Gestion des abonnements** : Panneau d'administration avec `admin_set_subscription` RPC. Un abonnement coûte 15 TND/mois avec `paid_until` sur la table `professionals`.
- **Sécurité RLS** : Row-Level Security complet sur `orders`, `messages`, `professionals`, `profiles`, `token_transactions`, `storage.objects` (buckets privés avec policies).

## Prérequis

- Flutter stable
- Dart 3
- Android Studio ou VS Code
- Un émulateur Android ou un appareil physique

## Lancer le projet

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## Générer un APK debug

```bash
flutter build apk --debug
```

Le fichier généré se trouve dans `build/app/outputs/flutter-apk/app-debug.apk`.

## Structure

- `lib/core` : thème, navigation, catalogue et modèles partagés
- `lib/features` : fonctionnalités organisées par domaine
- `lib/shared` : localisation et widgets réutilisables
- `test` : tests unitaires des stores et services
- `docs` : documentation et plan du projet

## Avant la production

1. **Push Notifications** : Finaliser l'intégration OneSignal avec `google-services.json` et `firebase_core`/`firebase_messaging` (déjà installés).
2. **Stockage médias** : Migrer `chat-media` et `documents` vers des buckets privés avec signed URLs.
3. **RLS complet** : Finaliser les règles de sécurité sur toutes les tables (orders, messages, professionals, profiles).
4. **Tests d'intégration** : Ajouter des tests E2E pour la환류 du compte complet (inscription → vérification → approbation).
5. **Documentation** : Compléter les textes légales (CGU, confidentialité, cookies) et les clues de configuration du projet.
