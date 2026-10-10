# Configurazione Supabase – progetto MILANAC

Progetto: `https://bxtnvgnxfyzwamfdnmkx.supabase.co`
**URL di callback** da usare in TUTTI i provider (Google, Microsoft, Yahoo, Apple):

```
https://bxtnvgnxfyzwamfdnmkx.supabase.co/auth/v1/callback
```

## 1. Database (automatico, tramite GitHub)
Le tabelle vengono create dal workflow **Database** di GitHub Actions.

**Modo consigliato – token personale:**
1. https://supabase.com/dashboard/account/tokens → **Generate new token** → nome `GitHub milanac` → copia il token (`sbp_…`).
2. GitHub → milanac-app → Settings → Secrets and variables → Actions → New repository secret:
   nome `SUPABASE_ACCESS_TOKEN`, valore il token.
3. Actions → **Database** → Run workflow.

**In alternativa – password del database:**
1. Dashboard Supabase → pulsante **Connect** in alto → scheda **Connection String** → metodo **Session pooler**
   → copia l'URI, tipo `postgresql://postgres.bxtnvgnxfyzwamfdnmkx:[YOUR-PASSWORD]@aws-…pooler.supabase.com:5432/postgres`.
2. Sostituisci `[YOUR-PASSWORD]` con la password del database (se non la ricordi: **Project Settings → Database →
   Reset database password**).
3. GitHub → repository **milanac-app** → **Settings → Secrets and variables → Actions → New repository secret**:
   nome `SUPABASE_DB_URL`, valore l'URI completo con la password.
4. **Actions → Database → Run workflow**. Nel log compare `✓` per ogni file applicato.
   Le migrazioni future si applicano da sole quando arrivano su `main`; quelle già eseguite vengono saltate.

In alternativa, a mano: SQL Editor → incolla ed esegui in ordine i file di `supabase/migrations/`.

## 2. URL dell'app
**Authentication → URL Configuration → Redirect URLs** → *Add URL*:
```
com.milanacproclub.milanac://login-callback
```

## 3. Google
1. https://console.cloud.google.com → nuovo progetto "MILANAC"
2. *API e servizi → Schermata consenso OAuth* → Esterno, nome app "MILANAC Pro Club", la tua email
3. *Credenziali → Crea credenziali → ID client OAuth* → tipo **Applicazione web**
   - URI di reindirizzamento autorizzati: l'URL di callback sopra
4. Copia **Client ID** e **Client secret** → Supabase → *Authentication → Providers → Google* → abilita e incolla.

## 4. Microsoft (Hotmail / Outlook / Live)
1. https://portal.azure.com → **Microsoft Entra ID → Registrazioni app → Nuova registrazione**
   - Nome "MILANAC Pro Club"
   - Tipi di account: **Account in qualsiasi directory organizzativa e account Microsoft personali**
   - URI di reindirizzamento (Web): l'URL di callback sopra
2. *Certificati e segreti → Nuovo segreto client* → copia il **Valore**
3. Supabase → *Providers → Azure* → abilita: **Application (client) ID**, **Secret Value**,
   Azure Tenant URL: `https://login.microsoftonline.com/common`

## 5. Yahoo
1. https://developer.yahoo.com/apps/ → *Create an App*
   - Redirect URI: l'URL di callback sopra
   - API Permissions: **OpenID Connect Permissions** → Email, Profile
2. Supabase → *Authentication → Providers* → **Add custom provider** (OIDC)
   - Identificativo: `yahoo`  (l'app lo chiama `custom:yahoo`)
   - Issuer URL: `https://api.login.yahoo.com`
   - Client ID e Client Secret dell'app Yahoo
   - Scopes: `openid email profile`

## 6. Apple (obbligatorio per l'App Store)
1. https://developer.apple.com/account → *Certificates, IDs & Profiles*
   - **Identifiers → App IDs**: `com.milanacproclub.milanac`, abilita *Sign in with Apple*
   - **Identifiers → Services IDs**: es. `com.milanacproclub.milanac.signin`, abilita *Sign in with Apple*,
     Domain: `bxtnvgnxfyzwamfdnmkx.supabase.co`, Return URL: l'URL di callback sopra
   - **Keys**: nuova chiave con *Sign in with Apple* → scarica il file `.p8` (si scarica una sola volta!)
2. Supabase → *Providers → Apple* → abilita, inserisci Services ID e genera il secret
   seguendo le istruzioni del pannello (Team ID, Key ID, file .p8).
   ⚠️ Il secret Apple scade ogni 6 mesi: va rigenerato (promemoria nel calendario!).

## 7. Email e password (conferma dell'email, password dimenticata)
Supabase invia le email di conferma e di recupero, ma il suo server di posta predefinito è solo
per le prove (pochi messaggi all'ora). Serve un servizio SMTP gratuito, per esempio **Resend**
(3.000 email al mese) o **Brevo** (300 al giorno):
1. Crea l'account sul servizio, verifica il dominio o l'indirizzo mittente e crea una **chiave SMTP**.
2. Supabase → **Project Settings → Authentication → SMTP Settings** → *Enable Custom SMTP*:
   host, porta, utente e password forniti dal servizio; mittente es. `MILANAC Pro Club <noreply@…>`.
3. **Authentication → Providers → Email**: lascia attivo *Confirm email* (chi si registra con email
   entra solo dopo aver aperto il link).
4. **Authentication → URL Configuration**: l'URL di reindirizzamento `com.milanacproclub.milanac://login-callback`
   deve essere tra i *Redirect URLs* (serve anche ai link di conferma e di recupero password).

## 8. Password del Direttivo
Chi si registra scegliendo "Faccio parte del Direttivo" deve inserire la **password del club**.
Nel database c'è solo il suo hash (`app_config`, chiave `direttivo_password_hash`), impostato dalla
migrazione `0016`. Si cambia dall'app: Impostazioni → Account → *Password del Direttivo*
(oppure dall'SQL Editor: `select set_direttivo_password('attuale', 'nuova')` eseguito come Direttivo).
Non serve più nominare il primo Direttivo a mano: basta registrarsi con la password.

## 9. Azzeramento dei dati
La migrazione `0016` svuota presenze, formazioni, eventi, risultati, trofei, tattiche, chat e tornei,
e riporta tutti i profili alla registrazione: ogni membro ripassa dai tre passi e dal regolamento.
I file nei bucket (foto, clip, trofei) non vengono cancellati: se servono spazio, svuotali da
**Storage** nel pannello di Supabase.

## 10. Notizie automatiche (GitHub Actions)
1. Su GitHub apri il repository **milanac-app** → **Settings → Secrets and variables → Actions**
2. **New repository secret**
   - Name: `SUPABASE_SECRET_KEY`
   - Secret: la chiave `sb_secret_…` (Supabase → Settings → API Keys)
3. Vai su **Actions → Notizie → Run workflow** per la prima raccolta.
   Nel log vedi, fonte per fonte, quante notizie sono arrivate (✓) o se è stata saltata (✗).
4. Da lì in poi parte da solo ogni 3 ore (alle :17).

> Nota: le esecuzioni programmate partono solo dal branch principale (`main`):
> il workflow si attiva da solo dopo il merge della pull request.

## 11. Lavori automatici delle presenze (pg_cron)
La migrazione `0017` attiva l'estensione **pg_cron** e programma `attendance_tick()` ogni minuto:
alle 18:00 (ora italiana) il promemoria a chi non ha risposto, alle 18:30 le assenze automatiche.
Se il workflow Database si ferma sulla riga `create extension if not exists pg_cron`, attiva
l'estensione a mano (Dashboard → **Database → Extensions** → cerca `pg_cron` → abilita) e rilancia
il workflow. Per controllare: SQL Editor → `select jobname, schedule from cron.job;` e
`select * from cron.job_run_details order by start_time desc limit 10;`.
Le notifiche (promemoria, assenze, eventi, video, notizie, carte speciali) partono dalla funzione
`notify`: il workflow **Funzioni** la ripubblica da solo quando il codice arriva su `main`.

## 12. Pulizia degli allegati della chat (pg_cron + funzione notify)
Foto e vocali della chat scadono dopo 60 giorni (il messaggio resta con "Allegato scaduto").
La migrazione `0018` programma `expire_attachments()` ogni notte alle 3:15 (ora del server):
toglie gli allegati scaduti dai messaggi, mette i file nella tabella `storage_cleanup` e chiama
la funzione `notify` con l'evento `cleanup`, che li elimina dal bucket `chat` con la chiave di
servizio (nessun segreto in più da configurare). I file dei messaggi eliminati seguono la stessa
strada. Se una notte la rimozione fallisce, le righe restano in coda e si riprova la notte dopo.
Per controllare: SQL Editor → `select * from storage_cleanup;` (vuota = tutto pulito) e
`select jobname, schedule from cron.job;` (devono esserci `presenze`, `pulizia-cron` e
`allegati-scaduti`).

## Sicurezza
- La chiave **publishable** (`sb_publishable_…`) è nel repository: va bene, è pensata per stare nell'app.
- La chiave **secret** (`sb_secret_…`) NON va mai messa nell'app né nel repository:
  servirà solo come *secret* di GitHub Actions per il job delle notizie.
