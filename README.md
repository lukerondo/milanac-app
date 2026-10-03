# MILANAC Pro Club – App

App ufficiale del **MILANAC Pro Club** (EA SPORTS FC 27 – Pro Clubs) per **Android** e **iOS**,
scritta in **Flutter** con backend **Supabase** (piano gratuito).

- Architettura e roadmap: [`docs/ARCHITETTURA.md`](docs/ARCHITETTURA.md)
- Prompt per video intro, albo d'oro e stemma: [`docs/PROMPT_GRAFICA.md`](docs/PROMPT_GRAFICA.md)
- Schema database + permessi: [`supabase/migrations/`](supabase/migrations)

## Stato

| Fase | Contenuto | Stato |
|---|---|---|
| 1 | Scheletro, tema rossonero, Intro, Login social, approvazione utenti, menu laterale, Home notizie | ✅ |
| 2 | Rosa (con approvazione accessi), Regolamento & Storia, contatti social modificabili | ✅ |
| 3 | Presenze con storico (notifiche push nella fase 8) | ✅ |
| 4 | Calendario, Risultati + media (link / foto / clip 15s) | ✅ |
| 5 | Formazione (campo San Siro, 7 moduli, panchina) | ✅ |
| 6 | Notizie automatiche (GitHub Actions) | ⏳ |
| 7 | Albo d'oro 2.5D | ⏳ |
| 8 | Pubblicazione Play Store / App Store | ⏳ |

## Provare l'app subito (modalità demo)

Senza configurare nulla l'app parte in **modalità demo**: niente login, dati di esempio.

```bash
flutter pub get
flutter run            # telefono/emulatore collegato
flutter run -d chrome  # nel browser
```

## Video intro

Metti il video in `assets/video/intro.mp4` (verticale 1080×1920, 10–15s, max ~8 MB).
Se il file non c'è, l'intro usa l'immagine `assets/images/intro_bg.png`.

## Collegare Supabase (gratis)

1. Crea un progetto su [supabase.com](https://supabase.com) (piano Free, regione Europa).
2. **SQL Editor** → incolla ed esegui, in ordine, i file in `supabase/migrations/`
   (`0001_schema_iniziale.sql`, poi `0002_limiti_media.sql`).
3. **Authentication → URL Configuration** → aggiungi agli *Redirect URLs*:
   `com.milanacproclub.milanac://login-callback`
4. **Authentication → Providers**:
   - **Google** – client OAuth da Google Cloud Console
   - **Azure** (Microsoft/Hotmail/Outlook) – app registrata su Azure con tenant `common`
     (account personali Microsoft abilitati)
   - **Apple** – obbligatorio su iOS (Services ID dal tuo account Apple Developer)
   - **Yahoo** – provider *Custom OIDC* con identificativo `yahoo`, issuer
     `https://api.login.yahoo.com`, client creato su developer.yahoo.com
5. Avvia l'app collegata al progetto (URL e chiave *publishable* sono in `env/prod.json`;
   la chiave publishable è pubblica per design, la sicurezza è data dalle policy RLS):
   ```bash
   flutter run --dart-define-from-file=env/prod.json
   ```
   **Non** inserire mai nel repository la chiave `secret` / `service_role`.
6. Fai il primo login, poi nell'SQL Editor nomina il primo Direttivo:
   ```sql
   update profiles set club_role = 'direttivo' where display_name = 'Il tuo nome';
   ```
   Da lì in poi è il Direttivo ad approvare gli altri dall'app.

## Build

- **CI**: ad ogni push GitHub Actions esegue `flutter analyze` e `flutter test`.
- **APK**: Actions → *CI* → *Run workflow* → scarica l'artifact `milanac-apk` (usa `env/prod.json`).
- **iOS**: tramite Codemagic (piano gratuito) o un Mac – istruzioni nella fase 8.

Identificativo app: `com.milanacproclub.milanac`
