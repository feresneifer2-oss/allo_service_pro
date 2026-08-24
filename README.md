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

Cette version utilise des stores locaux en mémoire pour permettre le développement et les démonstrations sans backend. Les données sont réinitialisées lorsque l'application redémarre.

L'intégration Firebase est volontairement prévue en dernière étape :

- Firebase Authentication
- Cloud Firestore
- Firebase Storage
- Firebase Cloud Messaging
- Règles de sécurité et rôles client/prestataire/admin

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

1. Intégrer Firebase et remplacer les données locales.
2. Retirer les identifiants admin locaux et gérer les rôles côté serveur.
3. Activer le vrai OTP, la réinitialisation du mot de passe et les sessions.
4. Ajouter le stockage des photos/documents et les notifications push.
5. Compléter les règles de sécurité, les pages légales et les tests d'intégration.
